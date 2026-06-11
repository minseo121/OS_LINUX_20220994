# 10주차 - 웹 서버 구축운영

## 서버 트렌드 이해

### 웹 서버 시장 현황
Nginx (약 34%) / Apache(약 28%) 역전은 2021년 경.

- **Apache** : 프로세스/스레드 기반. 연결이 들어올때마다 프로세스(스레드)를 하나씩 만들어서 처리. **연결 1개 = 프로세스 1개 점유**. 동시 접속자가 많아지면 그만큼 프로세스가 쌓이면서 메모리 급격히 증가.
- **Nginx** : 이벤트 기반 비동기 방식. 소수의 worker 프로세스가 수만 개의 연결을 동시에 처리. 연결마다 프로세스를 새로 만들지 않으니까 메모리 점유 비용 X

**왜 Nginx가 역전했는가?**
CDN이랑 리버스 프록시 수요가 급증하면서 수십만 개의 동시 연결을 처리해야 하는 상황이 일반화. 때문에 한계있는 Apache 대신 Nginx가 굿.

**최근에 Apache도 따라잡지 않았나?**
eventMPM을 통해 비동기 처리가 가능해졌지만, 내장 모듈들이 메모리를 많이 먹어서 여전히 메모리 사용량이 Nginx 대비 3~5배 수준.
Nginx는 PHP-FPM이나 upstream 처리를 외부 서버에 위임하는 방식이라 자기 자신은 가볍게 유지.

---

## 웹 서버 구축 준비

### 프로젝트 폴더 구조
~/linux/week10/
└── wordpress/
├── compose.yaml
├── .env
├── nginx/
│   └── default.conf
└── logs/

### Nginx 설정 파일 (default.conf)
Nginx가 들어오는 요청을 어떻게 처리할지 규칙을 정의.

**1. 기본 설정**
```nginx
listen 80;
server_name localhost;
root /var/www/html;
index index.php index.html;
client_max_body_size 64M;
```

**2. 기본 요청 처리 - location /**
```nginx
location / {
    try_files $uri $uri/ /index.php?$args;
}
```
`/about-us` 요청 → 파일 없음 → 디렉토리 없음 → `/index.php?args=about-us`로 넘김 → WordPress가 처리

**3. PHP 요청 전달 - location ~ \.php$**
```nginx
location ~ \.php$ {
    fastcgi_pass wordpress:9000;
    fastcgi_index index.php;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param PATH_INFO $fastcgi_path_info;
    fastcgi_read_timeout 300;
}
```
.php로 끝나는 요청만 WordPress 컨테이너(PHP-FPM)로 넘김. wordpress:9000에서 wordpress는 Docker 컨테이너 이름이 곧 DNS 역할.

**4. 정적 파일 캐싱 - location ~* \.(js|css|png|jpg)$**
```nginx
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
    expires 30d;
    add_header Cache-Control "public, no-transform";
    access_log off;
}
```
이미지, CSS, JS는 Nginx가 직접 서비스. 브라우저한테 30일 캐시 허용 → PHP-FPM 부하 감소, 응답 속도 향상.

**5. 보안 - location ~/\.(ht|git)**
```nginx
location ~ /\.(ht|git) {
    deny all;
}
```
.htaccess나 .git 폴더 외부 접근 차단.

> Nginx가 들어오는 요청에 따라 교통 정리.
> 정적 파일은 자기가 처리 / PHP만 WordPress로 넘기고 / 위험한 접근은 차단!

---

### compose.db.yaml
- .env에서 DB 이름, 비번 등 읽어옴
- 9주차에 만든 LVM 볼륨(`/mnt/mysql_data`)을 DB 저장소로 마운트
- wp_net 네트워크에 연결
- healthcheck: 10초마다 mysqladmin ping으로 확인, 실패하면 5번까지 재시도
  - WordPress 컨테이너가 DB 뜨기 전 먼저 실행되면 연결 오류 나기 때문에 `condition: service_healthy` 조건으로 DB healthy 확인 후에만 WordPress 기동

### compose.wordpress.yaml
- `depends_on: condition: service_healthy` → DB 완전히 뜬 다음에 WordPress 시작
- wp_data 볼륨을 Nginx랑 공유
- `external: false` → compose.db.yaml에서 이미 만든 볼륨/네트워크 재사용

### compose.nginx.yaml
- 외부 포트 노출은 Nginx만 (8080:80)
- wp_data 볼륨은 `:ro`(읽기 전용)로 마운트
- 로그는 호스트 `./logs`에 저장

---

## 단계적 검증 흐름

### STEP 1 - DB 단독 실행
```bash
docker compose -f compose.db.yaml up -d
docker compose -f compose.db.yaml ps
docker exec -it wp_db mysql -h 127.0.0.1 -u wpuser -pwppass_2026! -e "SHOW DATABASES;"
```
✅ wordpress DB 보이면 통과

### STEP 2 - DB + WordPress 병합
```bash
docker compose -f compose.db.yaml -f compose.wordpress.yaml up -d
docker exec wp_app getent hosts db
docker exec wp_app bash -c "cat < /dev/tcp/db/3306" 2>/dev/null && echo "연결 성공" || echo "연결 실패"
```
✅ DNS 해석 + 3306 포트 연결 성공하면 통과

### STEP 3 - 전체 실행
```bash
docker compose -f compose.db.yaml -f compose.wordpress.yaml down
docker compose -f compose.db.yaml -f compose.wordpress.yaml -f compose.nginx.yaml up -d
docker compose -f compose.db.yaml -f compose.wordpress.yaml -f compose.nginx.yaml ps
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080
```
✅ 301 또는 302 뜨면 통과

---

## WordPress 초기 설정
`http://localhost:8080` 접속 → 설치 마법사 진행 → 완료!
