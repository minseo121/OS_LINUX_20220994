# 9주차 - 파일시스템 관리 2

## 서버 트렌드 이해

### 서버 스토리지 계층

- **VFS(Virtual File System)** : App과 실제 파일시스템 사이의 공통 인터페이스
- **Page Cache/Buffer Cache** : CPU와 디스크 속도 차이를 메우기 위해 디스크 데이터를 RAM에 캐싱 → 모든 디스크 I/O가 이 계층을 경유
- **블록 계층(커널)** : I/O 요청을 병합하고 스케줄링해서 최적화. Page Cache 미스가 발생하면 실제 디스크로 내려감

```
애플리케이션 (Docker, MySQL)
        ↓
   VFS / 파일시스템 (ext4)
        ↓
   Page Cache
        ↓
★ 블록 계층 — Device Mapper (LVM)
        ↓
   loop 디바이스 (WSL2 환경이라 물리 디스크 대신)
        ↓
   물리 장치 (.img 파일)
```

### 블록 계층 : Device Mapper (dm-*)

커널 블록 매핑 프레임워크. 모든 가상 블록 장치의 기반.

> 커널이 물리 디스크들을 원하는 모양으로 포장해주는 도구

| dm 타겟 | 사용 도구 | 역할 |
|---|---|---|
| dm-linear | lvm2 | LVM 기본 LV |
| dm-thin | lvm2 | Thin Provisioning |
| dm-crypt | cryptsetup | 투명 디스크 암호화 (LUKS2, AES-XTS) |
| dm-cache | lvm2 | SSD를 HDD의 캐시로 사용 |
| dm-raid | mdadm | 소프트웨어 RAID |
| dm-thin | docker | 컨테이너 레이어 관리 |

---

## 디스크 관리 및 제한

### LVM 구조

```
물리 디스크 / 파티션
        ↓
PV (Physical Volume)   ← 디스크를 LVM이 쓸 수 있게 초기화한 상태
        ↓
VG (Volume Group)      ← PV들을 하나의 큰 풀(pool)로 묶은 것
        ↓
LV (Logical Volume)    ← VG에서 실제로 잘라서 쓰는 논리적 공간
                          여기에 mkfs, mount 해서 실제로 사용
```

---

### 디스크 A — /var/lib/docker 분리 (순차 I/O)

#### 디스크 추가
```bash
# 가상 디스크 파일 생성
sudo dd if=/dev/zero of=disk_a.img bs=1M count=3072

# loop 디바이스 연결
sudo losetup -fP --show disk_a.img   # → /dev/loop0
```

#### LVM 구성
```bash
sudo pvcreate /dev/loop0
sudo vgcreate vg_docker /dev/loop0
sudo lvcreate -l 100%FREE -n lv_docker vg_docker
```

#### 마운트 & 데이터 이관
```bash
# ext4 포맷
sudo mkfs.ext4 /dev/vg_docker/lv_docker

# Docker 중지 & 임시 마운트
sudo service docker stop
sudo mkdir /mnt/docker_new
sudo mount /dev/vg_docker/lv_docker /mnt/docker_new

# 데이터 복사 (메타데이터 보존)
sudo rsync -aHAX /var/lib/docker/ /mnt/docker_new/

# 원본 백업 & 실제 경로로 교체
sudo mv /var/lib/docker /var/lib/docker.backup
sudo mkdir /var/lib/docker
sudo umount /mnt/docker_new
sudo mount /dev/vg_docker/lv_docker /var/lib/docker
sudo service docker start
```

---

### 디스크 B — /var/lib/mysql 분리 (랜덤 I/O)

#### 디스크 추가
```bash
sudo dd if=/dev/zero of=disk_b.img bs=1M count=2072
sudo losetup -fP --show disk_b.img   # → /dev/loop1
```

#### LVM 구성
```bash
sudo pvcreate /dev/loop1
sudo vgcreate vg_mysql /dev/loop1
sudo lvcreate -L 1G -n lv_mysql vg_mysql   # 1GB 고정 (확장 실습용 여유 남김)
sudo mkfs.ext4 /dev/vg_mysql/lv_mysql
```

#### 영구 마운트 (fstab 등록)
```bash
sudo mkdir /mnt/mysql_data
sudo blkid /dev/vg_mysql/lv_mysql   # UUID 확인
sudo nano /etc/fstab
# UUID=xxxx /mnt/mysql_data ext4 defaults,noatime 0 2
sudo mount -a
```

#### MySQL 컨테이너 연결
```bash
docker run -d --name mysql_lab \
  --restart=unless-stopped \
  -e MYSQL_ROOT_PASSWORD=labpass \
  -v /mnt/mysql_data:/var/lib/mysql \
  -p 3306:3306 \
  mysql:8.0
```

#### LV 온라인 확장 (무중단)
```bash
sudo lvextend -L +500M /dev/vg_mysql/lv_mysql
sudo resize2fs /dev/vg_mysql/lv_mysql
# 결과: 1GB → 1.5GB 확장
```

---

### 디스크 A/B 비교

| 항목 | 디스크 A (Docker) | 디스크 B (MySQL) |
|---|---|---|
| 목적 | 순차 I/O 분리 | 랜덤 I/O 분리 |
| 이미지 크기 | 3GB | 2GB |
| loop 장치 | /dev/loop0 | /dev/loop1 |
| VG 이름 | vg_docker | vg_mysql |
| LV 할당 | 100%FREE | 1G 고정 |
| fstab 등록 | ❌ | ✅ UUID 등록 |
| 데이터 이관 | rsync -aHAX | 없음 (자동 초기화) |
| 온라인 확장 | 없음 | lvextend +500M → resize2fs |

---

### I/O 특성 비교 (fio 벤치마크)

| 항목 | 순차 읽기 (Docker LV) | 랜덤 읽기 (MySQL LV) |
|---|---|---|
| BW | 1,506MiB/s | 32.3MiB/s |
| IOPS | 1,505 | 8,276 |
| 평균 지연 | 661µs | 118µs |
| 블록 크기 | 1MB | 4KB |

---

## 실습문제 1 — /home 분리 + Quota

### 목표
70명 학생 홈 폴더 용량 제한

### 1. 패키지 설치 & 디스크 C 생성
```bash
sudo apt install -y quota quotatool
sudo dd if=/dev/zero of=disk_c.img bs=1M count=2048
sudo losetup -fP --show disk_c.img   # → /dev/loop2
```

### 2. LVM 구성
```bash
sudo pvcreate /dev/loop2
sudo vgcreate vg_home /dev/loop2
sudo lvcreate -l 100%FREE -n lv_home vg_home
sudo mkfs.ext4 /dev/vg_home/lv_home
```

### 3. fstab 등록 (quota 옵션 포함)
```bash
sudo mkdir /mnt/home_quota
sudo blkid /dev/vg_home/lv_home
sudo nano /etc/fstab
# UUID=xxxx /mnt/home_quota ext4 defaults,usrquota,grpquota 0 2
sudo mount -a
```

### 4. Quota 활성화
```bash
sudo quotacheck -cugvm /mnt/home_quota
sudo quotaon -v /mnt/home_quota
```

### 5. 사용자 용량 제한
```bash
sudo useradd -d /mnt/home_quota/student1 -m student1
sudo setquota -u student1 102400 122880 0 0 /mnt/home_quota
# soft 100MB(경고) / hard 120MB(즉시 차단)
```

### 6. 한계 테스트 결과
```bash
sudo -u student1 bash
dd if=/dev/zero of=~/test1 bs=1M count=150
# → Disk quota exceeded (120MB에서 차단)
```

---

## 실습문제 2 — setup_disks.sh

WSL 재시작 시 loop 연결이 끊기므로 자동 복구 스크립트 작성

```bash
#!/bin/bash
cd ~/linux/week09 || { echo "week09 폴더 없음"; exit 1; }

echo "=== loop 디바이스 재연결 ==="
if ! losetup -a | grep -q disk_a.img; then
    sudo losetup -fP disk_a.img && echo "disk_a.img 연결됨"
else
    echo "disk_a.img 이미 연결됨"
fi
if ! losetup -a | grep -q disk_b.img; then
    sudo losetup -fP disk_b.img && echo "disk_b.img 연결됨"
else
    echo "disk_b.img 이미 연결됨"
fi
if ! losetup -a | grep -q disk_c.img; then
    sudo losetup -fP disk_c.img && echo "disk_c.img 연결됨"
else
    echo "disk_c.img 이미 연결됨"
fi

echo "=== LVM 활성화 ==="
sudo vgchange -ay

echo "=== Docker LV 마운트 ==="
sudo mount /dev/vg_docker/lv_docker /var/lib/docker

echo "=== fstab 마운트 ==="
sudo mount -a

echo "=== Docker 시작 ==="
sudo service docker start

echo ""
echo "=== 디스크 상태 ==="
losetup -a
sudo lvs
df -hT | grep -E "vg_|loop|mysql"

echo ""
echo "=== Docker 상태 ==="
docker ps
```
