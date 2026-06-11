# 7주차 - 파일시스템 관리

## 1. 서버 트렌드 이해

### 서버 스토리지 계층이란?
서버에서 데이터를 저장하고 꺼내오는 모든 과정.
작동방식이 다양한데 그걸 다 신경쓸 수 없어서 계층이 나뉘어져 있음.
서버에서 특히 중요한 이유는 수백명이 동시에 읽고 쓰니까 **얼마나 빠르고 안전하게 저장되냐**가 중요함.

```
애플리케이션 (read, write 등)
       ↓
VFS (Virtual File System) - 모든 파일시스템의 공통 인터페이스
       ↓
파일시스템 계층 (ext4, XFS, Btrfs 등)  ← 7주차 집중!
       ↓
Page Cache / Buffer Cache
       ↓
블록 계층 (LVM, RAID 등)
       ↓
드라이버 계층 (nvme, io_uring 등)
       ↓
물리 장치 (NVMe SSD, HDD 등)
```

### EXT4 파일시스템 핵심 특징
- **저널링** : 갑자기 전원이 꺼져도 데이터 안 날아가게 보호 (무결성 보장, 장애 후 빠른 복구)
- **Extents 기반 블록 할당** : 연속된 블록을 묶음으로 관리 → 단편화 최소화
- **Delayed Allocation** : 쓰기 직전까지 블록 위치 결정을 미룸 → 효율적인 위치에 배치 가능

> Docker가 쓰는 overlay2 스토리지 드라이버가 EXT4 위에서 동작. EXT4가 overlay2를 완전 지원하기 때문에 Ubuntu 기본값으로 채택됨.

---

## 2. 파일 시스템 확인 및 제어

### 기본 명령어를 통한 FS 정보 확인

**`df -Th` : 기본 디스크 상태와 사용량**
```bash
df -Th
```
- `/dev/sdd ext4 1007G` → 실제 물리 파일시스템 (Docker도 여기에!)
- `overlay` → WSL 레이어 기반 가상 파일시스템
- `tmpfs` → 메모리 기반 임시 파일시스템 (재부팅 시 삭제)
- `9p` → 윈도우 드라이브 연결 (C:\, D:\)

**`lsblk -f` : 블록 디바이스 트리 구조**
```bash
lsblk -f
```

| 장치 | Type | 역할 |
|------|------|------|
| sda | ext4 | 가상 디스크 (Distro GUI 지원용) |
| sdb | ext4 | 가상 디스크 |
| sdc | swap | 가상 메모리 (RAM 부족 시 사용) |
| **sdd** | **ext4** | **실제 물리 파일시스템 + Docker도 여기에!** |

```bash
ls -al /dev/sda    # b: 블록 장치 확인, 용량은 안 나옴
sudo fdisk -l      # 세부 정보 확인 (용량, 섹터 수, 섹터 크기 등)
```

| 장치 | 크기 | 섹터 크기 |
|------|------|-----------|
| sda | 388MB | 512 bytes |
| sdb | 186MB | 512 bytes |
| sdc | 2GB | 512/4096 bytes (swap) |
| **sdd** | **1TB** | **512/4096 bytes ← 핵심!** |

> 섹터(512B) = 하드웨어 최소 단위 / 블록(4096B) = 파일시스템 최소 단위 (섹터 8개 묶음)

---

### Inode

**Inode = 파일의 신분증**
파일 이름으로 접근하면 OS가 Inode 번호를 찾고, Inode에서 실제 데이터 위치를 찾아가는 구조.

Inode에 담긴 것: 파일 권한/UID/GID, 타임스탬프, 블록 주소, Links 카운트

```bash
stat /etc/hosts    # Inode 정보 확인
df -i              # Inode 사용량 확인
```

| 항목 | 값 |
|------|-----|
| 최대 inode | 약 6700만개 |
| 현재 사용 | 174,077개 (1%) |

> Inode가 꽉 차면 디스크 용량이 남아도 파일을 못 만듦!

**실제 크기 vs 디스크 점유 크기**
```
/etc/hosts 실제 크기  : 427 bytes
디스크 실제 점유      : 8섹터 × 512 = 4096 bytes (1블록)
낭비                  : 3669 bytes
```
> 블록(4096 bytes)이 최소 단위라서 작은 파일도 4096bytes를 통째로 차지함

---

### 하드링크 vs 심볼릭링크

```bash
mkdir test && cd test
touch test
ln test hardlink       # 하드링크 생성
ln -s test symlink     # 심볼릭링크 생성
stat test hardlink symlink
```

| 항목 | test | hardlink | symlink |
|------|------|----------|---------|
| Inode | 46264 | **46264 (동일)** | **46265 (별개)** |
| Links | 2 | 2 | 1 |
| 타입 | regular file | regular file | symbolic link |
| Size | 0 | 0 | 4 (경로명 글자수) |

**원본 삭제 후**
```bash
rm test
cat hardlink   # 정상 출력
cat symlink    # No such file or directory (dangling link)
```

| | hardlink | symlink |
|---|---|---|
| 원본 삭제 후 | 정상 작동 | 깨짐 |
| 이유 | inode 공유라 데이터 유지 | 원본 경로가 끊어짐 |

> 하드링크 = 데이터 자체 공유 → 원본 삭제해도 살아있음 (백업 용도)
> 심볼릭링크 = 경로를 가리킴 → 원본 삭제하면 깨짐 (설정, 연결 등에 많이 씀)

---

### 각 폴더 공간 사용량

```bash
sudo du -ah --max-depth=1 /home | sort -hr
sudo du -sh /var/lib/docker    # 2.4G
```

### Docker 컨테이너 폴더 분석

```bash
sudo ls -F /var/lib/docker
docker info | grep -i "storage driver"    # Storage Driver: overlayfs
cat /proc/mounts | grep docker
```

```
/var/lib/docker/
├── overlay2/   ← 이미지 레이어 + 컨테이너 레이어
├── containers/ ← 컨테이너 메타데이터 + 로그
├── images/     ← 이미지 인덱스/메타데이터
├── volumes/    ← docker volume 데이터
├── network/    ← 네트워크 설정
└── buildkit/   ← 빌드 캐시
```

- Docker가 ext4 위에서 돌아가고 있음
- 각 컨테이너가 overlay로 마운트되어 있음
- `lowerdir` : 읽기 전용 이미지 레이어 (공유)
- `upperdir` : 컨테이너별 독립 레이어 (쓰기 가능)
- `df -Th`에 Docker가 안 보이는 이유 → WSL에서 별도 네임스페이스로 관리되기 때문!

---

## 3. 디스크 사용량 분석

| 항목 | 크기 |
|------|------|
| Docker 이미지 (공유) | ~1.4GB |
| overlay2 UpperDir (플러그인) | ~10.8GB |
| MySQL 데이터 파일 | ~23GB |
| WordPress 미디어 업로드 | ~1~5GB |
| 컨테이너 로그 | ~2~5GB |
| buildkit 빌드 캐시 | ~2~3GB |
| **총합** | **약 40~48GB** |

**현재 문제점**
`/var` 와 `/` 가 같은 파티션 → Docker, MySQL, 홈폴더가 전부 `/dev/sdd` 하나에 몰려있음
→ 하나라도 꽉 차면 시스템 다운 위험

**해결 방향**
```
/var/lib/docker           → 디스크 A 추가 (순차 I/O 최적화)
/var/lib/docker/volumes   → 디스크 B 분리 (랜덤 I/O 최적화)
/home                     → 독립 공간 + Quota 용량 제한
```

---

## 4. 실습문제 1 - 링크 생성 및 inode 확인

```bash
echo "linux filesystem" > origin.txt
ln origin.txt hard.txt
ln -s origin.txt sym.txt
ls -li origin.txt hard.txt sym.txt
```

**1. 각 파일의 inode 번호**

| 파일 | inode |
|------|-------|
| origin.txt | 46266 |
| hard.txt | **46266 (동일!)** |
| sym.txt | 46267 (별개) |

**2. sym.txt 맨 앞 문자**
`l` = symbolic link를 의미

**3, 4. 원본 삭제 후 동작**
```bash
rm origin.txt
cat hard.txt   # linux filesystem (정상 출력)
cat sym.txt    # No such file or directory
```

| | hard.txt | sym.txt |
|---|---|---|
| 원본 삭제 후 | 정상 작동 | 깨짐 (dangling link) |

---

## 5. 실습문제 2 - 직접/간접 포인터 테스트

```bash
dd if=/dev/zero of=tiny.bin bs=1K count=1
dd if=/dev/zero of=small.bin bs=1K count=40
dd if=/dev/zero of=medium.bin bs=1M count=1
dd if=/dev/zero of=large.bin bs=1M count=10
stat tiny.bin small.bin medium.bin large.bin
```

| 파일 | 실제 크기 | Blocks(섹터수) | 실제 점유 크기(Blocks×512) | 낭비 크기 |
|------|----------|----------------|---------------------------|----------|
| tiny.bin | 1 KB | 8 | 4 KB | **3 KB** |
| small.bin | 40 KB | 80 | 40 KB | 0 KB |
| medium.bin | 1 MB | 2048 | 1024 KB | 0 |
| large.bin | 10 MB | 20480 | 10240 KB | 0 |

> tiny.bin만 낭비 발생! 1KB짜리 파일인데 블록(4096bytes)이 최소 단위라서 4KB를 통째로 차지함.
> 40KB 이상부터는 블록에 딱 맞게 채워지니까 낭비 없음.
