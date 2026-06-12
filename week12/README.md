# 12주차 웹 서버 관리

## 서버 트렌드 이해

### 웹 보안의 3가지 핵심 계층

**1. 암호화 (Encryption)**

- 데이터를 전송할 때 TLS(Transport Layer Security) 프로토콜로 암호화
- 현재 최신 표준은 **TLS 1.3**
- 2030년 이내로 **PQC(양자 내성 암호, Post-Quantum Cryptography)** 전환 계획 중
    - 현재 사용하는 RSA-2048, ECC(P-256) 같은 기존 암호는 양자 컴퓨터가 등장하면 뚫릴 수 있음
    - PQC 알고리즘 예시: **ML-KEM-768 (Kyber)**
    - 단점: 공개키 크기가 기존 대비 약 37배, 서명 크기는 약 51배 커짐 → 통신 오버헤드 증가

**2. 시스템 보안 (System Security)**

- 서버 OS 하드닝(불필요한 서비스 제거, 설정 강화)
- IAM(Identity and Access Management): 접근 제어 → 최근 커널 수준 정책까지 확대
- AI 기반 위협 탐지 및 방지

**3. S/W 감사 (Software Audit)**

- 소스 코드 취약점 점검
- AI 기반 정적/동적 분석 도구 활용

### 2026년 주요 보안 위협

- AI의 무질서한 성장으로 인한 위협 확대
- 랜섬웨어 공격 고도화
- 오픈소스 및 공급망 공격 심화
- 국가 핵심 인프라 대상 위협

---

## Nginx HTTPS 설정

### HTTP vs HTTPS

| 항목 | HTTP | HTTPS |
| --- | --- | --- |
| 포트 | 80 | 443 |
| 암호화 | 없음 | SSL/TLS 보안 계층 적용 |
| 인증서 | 불필요 | 필요 |

### 인증서 종류

- **공인 CA 서명 인증서**: 공동인증서, 금융인증서, 민간인증서 등 신뢰할 수 있는 기관에서 발급
- **self-signed(자체 서명)**: OpenSSL로 직접 생성. 브라우저에서 신뢰하지 않아 경고 뜸. 개발/실습 용도로만 사용

---

### STEP 1. OpenSSL로 자체 서명 인증서 생성

```bash
mkdir certs
cd certs

openssl req -x509 -nodes \
  -days 365 \
  -newkey rsa:2048 \
  -keyout nginx-selfsigned.key \
  -out nginx-selfsigned.crt \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=SSU/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
```

| 옵션 | 설명 |
| --- | --- |
| `-x509` | 자체 서명 인증서 형식으로 생성 |
| `-nodes` | 개인키에 암호 설정 안 함 (Nginx가 자동 로드할 수 있게) |
| `-days 365` | 인증서 유효기간 1년 |
| `-newkey rsa:2048` | RSA 2048비트 키 새로 생성 |
| `-keyout` | 개인키 저장 파일명 |
| `-out` | 인증서 저장 파일명 |
| `-subj` | 인증서 주체 정보 (국가/시/조직/도메인) |
| `-addext` | Subject Alternative Name (SAN) 추가 - localhost와 127.0.0.1 허용 |

생성 후 파일 2개 생김:
- `nginx-selfsigned.crt` → 인증서 (공개, Nginx에 등록)
- `nginx-selfsigned.key` → 개인키 (**절대 외부 노출 금지!**)

```bash
# 인증서 내용 확인 (유효기간, 도메인 등)
openssl x509 -in nginx-selfsigned.crt -text -noout | grep -E "(Subject|Not Before|Not After|DNS)"
```

---

### STEP 2. Nginx 설정 파일(default.conf) 수정

**반드시 백업 먼저!**

```bash
cp default.conf default1.conf
sudo nano default.conf
```

**설정 내용 (맨 위에 80 포트 리다이렉트 블록 추가):**

```nginx
# 80 포트로 들어오면 HTTPS(8443)로 강제 이동
server {
    listen 80;
    server_name localhost;
    return 301 https://$host:8443$request_uri;
}

# 기존 server 블록의 listen 포트를 443으로 변경
server {
    listen 443 ssl;
    server_name localhost;

    # 인증서 경로 지정
    ssl_certificate     /etc/nginx/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/nginx/certs/nginx-selfsigned.key;

    # TLS 1.3만 허용 (구버전 차단)
    ssl_protocols TLSv1.3;
    ssl_prefer_server_ciphers off;

    # OWASP 권장 보안 헤더
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    # ... 기존 WordPress 설정 유지 ...
}
```

### 보안 헤더 설명

| 헤더 | 역할 | 차단 공격 |
| --- | --- | --- |
| `X-Frame-Options: SAMEORIGIN` | 같은 출처에서만 iframe 허용 | Clickjacking |
| `X-Content-Type-Options: nosniff` | 브라우저가 MIME 타입 임의 변경 금지 | MIME 스니핑 |
| `X-XSS-Protection: 1; mode=block` | XSS 감지 시 페이지 차단 | XSS (구형 브라우저) |
| `Strict-Transport-Security` | 1년간 HTTPS만 허용 강제 | HTTP 다운그레이드 |
| `Referrer-Policy` | 외부 사이트로 URL 정보 제한 | 정보 유출 |

### 리다이렉트 설정 설명

| 코드 | 의미 |
| --- | --- |
| `return 301 ...` | Moved Permanently - 영구 이동 (SEO에도 영향) |
| `https://$host:8443$request_uri` | HTTPS 프로토콜의 8443 포트로 강제 전환 |

---

### STEP 3. compose.nginx.yaml 수정

```yaml
services:
  nginx:
    image: nginx:alpine
    container_name: wp_nginx
    ports:
      - "8080:80"
      - "8443:443"   # ← 443 포트 추가
    volumes:
      - wp_data:/var/www/html:ro
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ./nginx/certs:/etc/nginx/certs:ro   # ← 인증서 폴더 마운트 추가
      - ./logs:/var/log/nginx
    depends_on:
      - wordpress
    networks:
      - wp_net
    restart: unless-stopped
```

| 포트 | 컨테이너 포트 | 프로토콜 | 용도 |
| --- | --- | --- | --- |
| 8080 | 80 | HTTP | 웹 요청 수신 → HTTPS 리다이렉트 |
| 8443 | 443 | HTTPS | TLS 1.3 암호화 통신 |

**컨테이너 재시작:**

```bash
docker compose \
  -f compose.db.yaml \
  -f compose.wordpress.yaml \
  -f compose.nginx.yaml \
  up -d --force-recreate nginx
```

---

### STEP 4. 설정 적용 및 검증

```bash
# 설정 파일 내용 확인
docker exec wp_nginx cat /etc/nginx/conf.d/default.conf

# Nginx 문법 검사
docker exec wp_nginx nginx -t

# 재시작 없이 설정 반영
docker exec wp_nginx nginx -s reload

# 보안 헤더 적용 확인
curl -k -I https://localhost:8443 | grep -E "(X-Frame|X-Content|Strict|X-XSS)"

# 테스트 1: HTTPS 응답 코드 확인 (200이면 성공)
curl -k -o /dev/null -w "%{http_code}" https://localhost:8443

# 테스트 2: HTTP → HTTPS 리다이렉트 확인 (301 응답 확인)
curl -I http://localhost:8080

# 테스트 3: 인증서 유효기간 확인
echo | openssl s_client -connect localhost:8443 2>/dev/null | openssl x509 -noout -dates

# 테스트 4: TLS 1.2 차단 확인 (handshake 실패해야 정상)
openssl s_client -connect localhost:8443 -tls1_2 2>/dev/null | grep "handshake"

# 테스트 5: TLS 1.3 동작 확인 (Protocol: TLSv1.3 출력되면 성공)
openssl s_client -connect localhost:8443 -tls1_3 2>/dev/null | grep "Protocol"

# 테스트 6: 협상된 암호 스위트 확인
openssl s_client -connect localhost:8443 -tls1_3 2>/dev/null | grep "Cipher"
```

---

### STEP 5. WordPress DB URL 수정

```bash
# DB에서 siteurl, home 값을 HTTPS 주소로 업데이트
docker exec wp_db mysql -u wpuser -pwppass_2026! wordpress -e "
UPDATE wp_options SET option_value='https://localhost:8443' WHERE option_name='siteurl';
UPDATE wp_options SET option_value='https://localhost:8443' WHERE option_name='home';
"

# 변경 확인
docker exec wp_db mysql -u wpuser -pwppass_2026! wordpress -e "
SELECT option_name, option_value FROM wp_options
WHERE option_name IN ('siteurl','home');
"

# wp-config.php에 강제 설정 추가
docker exec wp_app sh -c "
sed -i \"/table_prefix/i define('WP_HOME','https://localhost:8443');\ndefine('WP_SITEURL','https://localhost:8443');\" \
/var/www/html/wp-config.php
"

# 적용 후 확인
docker exec wp_app cat /var/www/html/wp-config.php | grep -n "SITE\|HOME\|table_prefix"

# wp_app 컨테이너 재시작
docker restart wp_app

# 리다이렉트 확인
curl -I http://localhost:8080/wp-admin/
```

> 브라우저에서 https://localhost:8443 접속 시 "연결이 안전하지 않음" 경고가 뜨면 고급 → 계속 클릭. self-signed 인증서라 브라우저가 신뢰하지 않는 것으로, 개발 환경에선 정상.

---

## Lynis 시스템 보안 감사

### Lynis란?

- 오픈소스 **시스템 보안 감사 도구**
- 에이전트 없이 로컬에서 실행
- 500개 이상의 항목을 자동 검사
- 결과를 **Hardening Index (0~100점)** 으로 수치화

### 감사 항목

- 부트 보안: GRUB 설정, 부트로더
- 파일시스템: 마운트 옵션, 권한
- SSH 설정: root 로그인 차단, 포트, 키 설정
- 사용자 계정: 패스워드 정책, sudo 권한
- 네트워크: 열린 포트, 방화벽 설정
- 로깅: syslog, auditd
- 컨테이너: Docker 보안 설정

### 결과 등급

| 결과 | 의미 |
| --- | --- |
| `[OK]` | 안전한 설정 |
| `[WARNING]` | 즉시 조치 필요 |
| `[SUGGESTION]` | 개선 권장 |

### Hardening Index 기준

| 점수 | 평가 |
| --- | --- |
| 0 ~ 49 | 위험 (즉시 조치) |
| 50 ~ 69 | 보통 (개선 필요) |
| 70 ~ 84 | 양호 |
| 85 ~ 100 | 우수 (실무 목표) |

---

### 설치 및 실행

```bash
sudo apt-get update
sudo apt install lynis -y

# 전체 시스템 감사 실행 (수분 소요)
sudo lynis audit system
```

**보고서 저장 위치:**
- `/var/log/lynis.log` → 전체 상세 로그
- `/var/log/lynis-report.dat` → 구조화된 결과

---

### 취약점 확인 및 조치

```bash
# WARNING 취약점 목록 확인
grep "^warning" /var/log/lynis-report.dat

# SUGGESTION 취약점 상위 10개 확인
grep "^suggestion" /var/log/lynis-report.dat | head -10
```

**주요 취약 항목과 조치 방법:**

| 항목 | 내용 | 우선순위 | 조치 방법 |
| --- | --- | --- | --- |
| PKGS-7392 | 취약 패키지 존재 | 높음 | 보안 패치 업그레이드 |
| DEB-0880 | fail2ban 미설치 | 중간 | `sudo apt install fail2ban -y` |
| AUTH-9230 | 패스워드 해싱 강화 필요 | 중간 | `/etc/login.defs`에서 SHA_CRYPT_MIN_ROUNDS 설정 |
| KRNL-5820 | core dump 활성화 상태 | 낮음 | core dump 비활성화 설정 |
| DEB-0280 | libpam-tmpdir 미설치 | 낮음 | 해당 패키지 설치 |

```bash
# PKGS-7392: 업그레이드 가능한 패키지 목록 확인
sudo apt list --upgradable 2>/dev/null

# 보안 패치만 실행
sudo unattended-upgrade -v -o 'Unattended-Upgrade::OnlyOnACPower=false'

# DEB-0880: fail2ban 설치
sudo apt install fail2ban -y

# AUTH-9230: 패스워드 해싱 강화
sudo nano /etc/login.defs
# SHA_CRYPT_MIN_ROUNDS 주석 해제 후 10000으로 설정
# SHA_CRYPT_MAX_ROUNDS 주석 해제 후 65536으로 설정

# 조치 후 재스캔
sudo lynis audit system

# Docker 환경 보안 상태 확인
sudo lynis audit system 2>/dev/null | grep -i -A2 "docker"
```

> WSL2 환경에서 docker.service, fail2ban.service 등이 UNSAFE로 표시되는 건 정상 현상

---

## Trivy 취약점 스캔

### Trivy란?

- 컨테이너 이미지의 **CVE(Common Vulnerabilities and Exposures)** 취약점을 자동으로 스캔하는 도구
- 내부 패키지를 CVE DB와 비교해서 취약점 탐지
- OS 패키지(apt, apk), 언어 라이브러리(pip, npm), 비밀 정보(API 키, 패스워드) 검사

### CVE 심각도 등급

| 등급 | 의미 |
| --- | --- |
| CRITICAL | 즉시 조치 필요 |
| HIGH | 조속히 대응 필요 |
| MEDIUM | 일반적 우선순위 |
| LOW | 낮은 위험도 |
| UNKNOWN | 등급 미분류 |

> 실무에서는 **CRITICAL과 HIGH 먼저 처리**

---

### 설치

```bash
# 1. 사전 패키지 설치
sudo apt-get install wget apt-transport-https gnupg lsb-release -y

# 2. GPG 공개키 등록
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null

# 3. 저장소 등록
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
https://aquasecurity.github.io/trivy-repo/deb \
$(lsb_release -sc) main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list

# 4. 설치 및 버전 확인
sudo apt-get update && sudo apt-get install trivy -y
trivy --version
```

---

### 스캔 실행

```bash
# 취약점 DB 업데이트
trivy image --download-db-only

# 이미지 스캔
trivy image nginx:alpine
trivy image wordpress:php8.2-fpm

# HIGH, CRITICAL만 필터링
trivy image --severity HIGH,CRITICAL wordpress:php8.2-fpm

# 패치 가능한 것만 보기
trivy image --severity CRITICAL --ignore-unfixed wordpress:php8.2-fpm

# 결과 저장 (JSON)
trivy image --severity HIGH,CRITICAL --format json --output trivy_wordpress.json wordpress:php8.2-fpm

# 결과 저장 (테이블)
trivy image --severity HIGH,CRITICAL --format table --output trivy_report.txt wordpress:php8.2-fpm
```

### 결과 항목 설명

| 컬럼 | 설명 |
| --- | --- |
| Library | 취약점이 있는 패키지 이름 |
| Vulnerability | CVE 번호 |
| Severity | 심각도 (CRITICAL/HIGH/MEDIUM/LOW) |
| Status | fixed(패치 버전 있음) / affected(아직 없음) |
| Installed Version | 현재 설치된 버전 |
| Fixed Version | 패치된 버전 (있으면 업그레이드 가능) |
| Title | 취약점 요약 설명 |

---

### 전체 컨테이너 일괄 스캔

```bash
# 현재 실행 중인 이미지 목록 확인
docker ps --format "{{.Image}}"

# 전체 일괄 스캔
for IMAGE in $(docker ps --format "{{.Image}}"); do
  echo "===== $IMAGE ====="
  trivy image \
    --severity HIGH,CRITICAL \
    --quiet \
    $IMAGE
done
```

### 전체 스캔 결과 비교

| 이미지 | HIGH | CRITICAL |
| --- | --- | --- |
| wordpress:php8.2-fpm | 144 | 14 |
| netdata/netdata:stable | 73+19 | 8 |
| nginx:alpine | 15 | 2 |
| mysql:8.0 | 0 | 1 |

> **가장 위험한 이미지 → wordpress:php8.2-fpm**

---

### MySQL 8.0 컨테이너 취약성 세부 분석

```bash
trivy image --severity CRITICAL mysql:8.0
```

- **CVE 번호**: CVE-2025-68121
- **취약점 설명**: Go의 `crypto/tls` 패키지에서 TLS 세션 재개(Session Resumption) 시 인증서 검증이 누락되는 취약점. `Config.Clone` 또는 `GetConfigForClient`로 TLS 설정을 변경한 경우, 재개된 핸드셰이크에서 이미 취소된 인증서가 유효한 것처럼 통과될 수 있음
- **CVSS 점수**: 10.0 (CRITICAL)
- **공격 유형**: 네트워크 기반 원격 공격 / 인증서 검증 우회 (CWE-295: Improper Certificate Validation)
- **해결 방법**: Fixed 버전 존재 → gosu를 Go 1.24.13 / 1.25.7 / 1.26.0 이상으로 재컴파일된 버전으로 업데이트. 실질적으론 mysql 이미지 최신 버전으로 업데이트하면 해결됨
- **Fixed 버전**: Go 1.24.13, 1.25.7, 1.26.0-rc.3 이상
