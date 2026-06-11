#!/bin/bash

# week09 폴더로 이동 (img 파일 위치)
cd ~/linux/week09 || { echo "week09 폴더 없음"; exit 1; }

# 1. loop 디바이스 재연결 (이미 연결됐으면 건너뜀)
echo "=== loop 디바이스 재연결 ==="
if ! losetup -a | grep -q disk_a.img; then
    sudo losetup -fP disk_a.img
    echo "disk_a.img 연결됨"
else
    echo "disk_a.img 이미 연결됨"
fi

if ! losetup -a | grep -q disk_b.img; then
    sudo losetup -fP disk_b.img
    echo "disk_b.img 연결됨"
else
    echo "disk_b.img 이미 연결됨"
fi

if ! losetup -a | grep -q disk_c.img; then
    sudo losetup -fP disk_c.img
    echo "disk_c.img 연결됨"
else
    echo "disk_c.img 이미 연결됨"
fi

# 2. LVM 활성화
echo "=== LVM 활성화 ==="
sudo vgchange -ay

# docker LV 마운트
echo "=== Docker LV 마운트 ==="
sudo mount /dev/vg_docker/lv_docker /var/lib/docker

# 3. fstab 마운트 (/mnt/mysql_data)
echo "=== fstab 마운트 ==="
sudo mount -a

# 4. Docker 시작
echo "=== Docker 시작 ==="
sudo service docker start

# 5. 상태 확인
echo ""
echo "=== 디스크 상태 ==="
losetup -a
sudo lvs
df -hT | grep -E "vg_|loop|mysql"

echo ""
echo "=== Docker 상태 ==="
docker ps
