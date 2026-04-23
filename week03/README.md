# 3, 4주차 - 계정 및 권한 관리

## Docker Compose로 컨테이너 관리

컨테이너 여러 개를 한 번에 관리하는 도구.
`docker-compose.yml` 파일 하나로 정의하고 명령어 하나로 전부 실행/종료.

```yaml
version: '3.8'
services:
  nginx-server:
    image: nginx:1.25-alpine
    container_name: my-web-proxy
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./html:/usr/share/nginx/html
    networks:
      - web-net
networks:
  web-net:
    driver: bridge
```

```bash
sudo apt install docker-compose
docker-compose up -d
docker-compose ps
docker-compose stop / start
docker-compose down
docker-compose down -v  # 볼륨까지 삭제
```

---

## 웹 서버 계정 및 파일 권한 제어

RBAC : 역할 기반 접근 제어. 최소 권한 원칙.

```bash
getent group
getent group www-data
sudo chgrp www-data html/pds
sudo chmod 755 html/pds
```

umask : 파일/폴더 생성 시 기본 권한 설정
- 022 → 파일 644, 폴더 755
- 077 → 파일 600, 폴더 700 (본인만 접근)

```bash
sudo visudo
# web_min ALL=(ALL) NOPASSWD: /usr/bin/docker-compose restart
```

---

## 계정 생성 자동화

/etc/skel : 신규 계정 생성 시 홈 폴더로 자동 복사되는 템플릿 폴더
- .profile : 로그인 환경 (umask 077 설정)
- .bashrc : 쉘 동작 (히스토리 시간 기록)
- .bash_logout : 로그아웃 동작

```bash
# create_user.sh
#!/bin/bash
for i in {1..20}
do
    useradd -m -s /bin/bash "student$i"
    echo "student$i:password!" | chpasswd
    chage -d 0 "student$i"
done
```

MOTD 수정 : /etc/update-motd.d/00-header 수정 후 run-parts로 확인

---

## 팀 공유 폴더

```bash
sudo groupadd dev_team1
sudo usermod -aG dev_team1 student1  # 1~5 반복

sudo chgrp dev_team1 html/
sudo chmod 770 html/

sudo gpasswd -d student3 dev_team1  # 탈퇴
sudo gpasswd -d student4 dev_team1
grep "dev_team1" /etc/group  # 확인
```

---

## 실습 문제

### 권한 변경 - web_min 실행 권한만 부여

```bash
sudo visudo
# web_min ALL=(ALL) NOPASSWD: /usr/bin/docker-compose start
# start만 명시 → restart, stop은 자동으로 제한됨
```

### 계정 삭제 (6~20번)

```bash
sudo nano delete_user.sh
```

```bash
#!/bin/bash
for i in {6..20}
do
    userdel -r "student$i"
done
```

```bash
sudo chmod +x delete_user.sh
sudo ./delete_user.sh
# student13은 사용 중이라 별도 삭제 필요
# sudo userdel -r student13
```

### 웹서비스 폴더 설정

```bash
# 1. student 1~5 그룹 추가
sudo usermod -aG dev_team1 student1
sudo usermod -aG dev_team1 student2
sudo usermod -aG dev_team1 student3
sudo usermod -aG dev_team1 student4
sudo usermod -aG dev_team1 student5

# 2. 폴더 소유 그룹 변경 + 외부인 접근 차단
sudo chgrp dev_team1 /home/minseo/linux/week03/web_service/html
sudo chmod 770 /home/minseo/linux/week03/web_service/html

# 3. 3, 4번 탈퇴
sudo gpasswd -d student3 dev_team1
sudo gpasswd -d student4 dev_team1

# 4. 확인
grep "dev_team1" /etc/group
# dev_team1:x:1025:student1,student2,student5
```
