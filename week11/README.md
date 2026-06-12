## 서버 트렌드 이해

### 컨테이너 오케스트레이션 표준화

| 도구 | 규모 | 특징 | 한계 |
| --- | --- | --- | --- |
| **Docker Compose** | 소규모 | 기본 실행 자동화 | 운영 장애 복구·스케일링 수동, dockerd가 항상 root 실행 (보안 취약) |
| **Kubernetes** | 대규모 | 멀티 노드 클러스터, 배포·스케일링·복구 완전 자동화, RBAC 제어 | 관리 난이도 높음, 보안·버전 관리 복잡 |
- 2022년 Docker Desktop 유료화 (기업 월 $5~21/인) → root 권한 없는 무료 대안 수요 증가
- Kubernetes가 현재 대규모 컨테이너 관리의 사실상 표준

### AI/ML 분야 자원 관리 이슈

- **GPU 단편화** - GPU 자원 낭비 문제
- **동적 스케줄링 부족** - 분산 처리 어려움
- **무거운 컨테이너 이미지** - 데이터 로딩 지연, I/O 병목
- **IP 주소 고갈**, 노드 간 트래픽 비용

| 워크플로우 단계 | 주요 오픈소스 | 역할 |
| --- | --- | --- |
| 전과정 통합 관리 | Kubeflow, Flyte | 파이프라인 시각화, 실험 추적 |
| 파이프라인 제어 | Argo Workflows | 순차/병렬(DAG 기반) 태스크 자동화 |
| 분산 학습 연산 | KubeRay, MPI Operator | PyTorch 등 분산 학습 클러스터 구성 |
| 추론 배포 | KServe, VLLM, KAITO | 서버리스 기반 초고속 추론 API 배포 |

---

## DOCKER 관리 - Portainer

### Portainer 개요

| 항목 | Docker | Portainer |
| --- | --- | --- |
| 역할 | 컨테이너 런타임 엔진 | Docker 관리 Web GUI |
| 성격 | 인프라 (Infrastructure) | 도구 (Management Tool) |
| 작동 방식 | 명령어 (CLI) | 브라우저 (GUI) |
| 설치 위치 | 호스트 OS에 직접 설치 | Docker 컨테이너로 실행 |
| 관계 | 본체 | Docker 위에서 동작 |
- 오픈 소스 (CE 버전 무료), 리소스 모니터링·이미지·볼륨 관리, Docker Compose 지원
- Docker 소켓(`/var/run/docker.sock`)을 마운트해서 Docker 엔진에 접근

### Portainer 설치 - compose.manage.yaml

```yaml
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: wp_portainer
    ports:
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock  # Docker 소켓 연결
      - portainer_data:/data                        # 설정 영구 저장
    networks:
      - wp_net
    restart: unless-stopped

volumes:
  portainer_data:

networks:
  wp_net:
    external: true        # 10주차 네트워크 재사용
    name: wordpress_wp_net
# 9443 : HTTPS (자체 인증서 내장, 별도 설정 X)
```

**실행 명령어**

```bash
# 컨테이너 실행
docker compose -f compose.manage.yaml up -d portainer

# 실행 확인
docker ps | grep portainer

# 브라우저 접속 (자체 서명 인증서이므로 "고급 → 계속 진행" 클릭)
<https://localhost:9443>
```

**최초 설정**: 관리자 계정 생성 → Get Started → local 환경 선택

### Portainer UI 탐색

**Containers 메뉴**

- 컨테이너 목록 (wp_db / wp_app / wp_nginx / wp_portainer) 확인
- Status, Image, Created, Ports 확인
- 컨테이너 클릭 시:
    - **Inspect 탭**: 상세 JSON 정보
    - **Stats 탭**: CPU/메모리 실시간 그래프
    - **Logs 탭**: 접근 로그 확인

**각 메뉴 확인 항목**

| 메뉴 | 확인 내용 |
| --- | --- |
| Volumes | wordpress_wp_data (Driver: local, Mountpoint 경로), portainer_data |
| Images | nginx:alpine / wordpress:php8.2-fpm / mysql:8.0 / portainer-ce (Size 비교) |
| Networks | wordpress_wp_net에 연결된 컨테이너 목록 및 IPv4 주소 |
| Stacks | Docker Compose 프로젝트 단위 관리 (wordpress, week11) |

---

## 웹 서버 모니터링 - Netdata

### Netdata 개요

- 웹 서버 내부 정보 자동 수집, CE 버전 무료
- 1초 단위(Per-second) 실시간 수집, 무제한 메트릭 및 로그 수집
- `/nginx_status` 엔드포인트 폴링 → Active connections / requests/sec 수집
- Docker 이미지 제공, 공식 사이트: https://www.netdata.cloud/

### 사전 설정 - Nginx stub_status 활성화

Netdata가 Nginx 메트릭을 수집하려면 `default.conf`에 아래 블록 추가 필요:

```
# Netdata 모니터링용 stub_status
location /nginx_status {
    stub_status on;
    # Docker 내부 네트워크만 허용
    allow 172.0.0.0/8;
    deny all;
}
```

```bash
# 설정 적용
cd ~/linux/week10
sudo nano wordpress/nginx/default.conf  # 서버 블록 안에 삽입

# Nginx 재시작
docker restart wp_nginx

# stub_status 동작 확인
curl <http://localhost:8080/nginx_status>
```

### Netdata 설치 - compose.manage.yaml에 서비스 추가

```yaml
netdata:
  image: netdata/netdata:latest
  container_name: wp_netdata
  ports:
    - "19999:19999"
  volumes:
    - /proc:/host/proc:ro
    - /sys:/host/sys:ro
    - /var/run/docker.sock:/var/run/docker.sock:ro
  cap_add:
    - SYS_PTRACE
  security_opt:
    - apparmor:unconfined
  networks:
    - wp_net
  restart: unless-stopped
```

```bash
# 실행 (~200MB 이상 다운로드)
docker compose -f compose.manage.yaml up -d netdata

# 접속
<http://localhost:19999>
# 첫 화면 하단 "Skip and use..." 클릭
```

### Netdata UI 탐색

| 탭/메뉴 | 확인 내용 |
| --- | --- |
| Nodes | 로컬 서버 성능 통계 (CPU, 메모리, Disk I/O, 네트워크) |
| Metrics → nginx | active connections (현재 연결 수), requests/sec (초당 요청 수) |
| Metrics → Docker | 컨테이너별 CPU / 메모리 사용량 비교 |
| Apps (우측) | 내부 애플리케이션별 CPU/메모리 사용량 |
| Containers & VMs | 컨테이너별 실시간 자원 사용량 |
| Network | 전체 트래픽, inode 사용량, 인/아웃바운드 분리 |

> Live, Log 등 일부 탭은 Netdata 계정 연동 필요
> 

### Netdata 계정 연동 (클라우드 대시보드)

- https://app.netdata.cloud/ 접속 (구글 등 소셜 로그인 무료)
- DOCKER → Compose 탭에서 claim 토큰 발급
- `compose.manage.yaml`의 netdata 서비스에 아래 환경 변수 추가:

```yaml
environment:
  - NETDATA_CLAIM_TOKEN=제공값
  - NETDATA_CLAIM_URL=제공값
```

클라우드 연동 시 **AI Insights** 기능 사용 가능:

- **Anomaly Analysis**: 이상 징후 자동 탐지 보고서
- **Performance Optimization**: 성능 최적화 보고서

---

## 부하 테스트 - Apache Bench (ab)

### 개요 및 핵심 지표

```bash
# 설치
sudo apt-get update
sudo apt install apache2-utils -y

# 기본 명령어 구성
ab -n [총_요청_수] -c [동시_요청_수] [대상_URL]
```

| 지표 | 의미 |
| --- | --- |
| Requests per second (RPS) | 초당 처리한 요청 수 = 처리량(Throughput) |
| Time per request (mean) | 요청과 응답에 걸린 평균 시간(Latency) |
| Failed requests | 실패한 요청 수 (2xx 외 응답코드 or 커넥션 타임아웃) |

### 주요 옵션

| 옵션 | 명칭 | 설명 |
| --- | --- | --- |
| `-n` | Number of requests | 총 요청 횟수 지정 (기본값: 1) |
| `-c` | Concurrency | 동시 요청 수 (가상 사용자 수) |
| `-t` | Timelimit | 최대 테스트 시간(초) |
| `-k` | KeepAlive | HTTP KeepAlive 활성화, TCP 연결 재사용 |
| `-p` | POST file | POST 요청 시 데이터 파일 경로 지정 (-T와 함께 사용) |
| `-T` | Content-type | POST/PUT 데이터의 Content-Type 지정 |
| `-H` | Custom Header | Authorization 토큰, Cookie 등 커스텀 헤더 추가 |
| `-v` | Verbosity | 출력 로그 상세 수준 설정 |

### HTTP 상태 코드 참고

| 코드 | 의미 |
| --- | --- |
| 200 | 성공 |
| 201 (PUT) | 성공, 리소스 생성 성공 |
| 301 | 리다이렉트, 리소스가 다른 장소로 변경됨 |
| 303 | 리다이렉트, Client에서 자동으로 새로운 리소스로 요청 처리 |
| 400 | 요청 오류, 파라미터 에러 |
| 401 | 권한없음 (인증 실패) |
| 404 | 리소스 없음 (페이지를 찾을 수 없음) |
| 500 | 서버 내부 에러 |
| 503 | 서비스 정지 (점검 등) |

---

## 부하 분석 결과 비교

### 테스트 1: 동적 페이지 부하 (index.php)

```bash
ab -n 2000 -c 50 <http://localhost:8080/> &
```

**wp_nginx (요청 수신 후 wp_app으로 전달, 비교적 부하 적음)**

| 항목 | 수치 | 해석 |
| --- | --- | --- |
| CPU | 0% → 9% 소폭 증가 | 이벤트 기반 비동기 처리, CPU 거의 안 씀 |
| Memory | 30MB 고정 | 요청 수와 무관하게 안정적 |
| Network RX | 900MB → 1GB | 클라이언트(ab)로부터 요청 수신 |
| Network TX | 900MB → 1GB | 클라이언트에게 응답 전송 |
| I/O | Read 8MB / Write 12MB | 로그 파일 기록 |

> **핵심**: Nginx는 요청 2000개에도 CPU 9% → 이벤트 기반 설계의 효율성 증명
> 

**wp_app (PHP-FPM 동적 처리, 급격한 부하 증가)**

| 항목 | 수치 | 해석 |
| --- | --- | --- |
| CPU | 0% → 420% 급등 | PHP-FPM 프로세스 다수 동시 실행 (코어 4개 이상 풀가동) |
| Memory | 134MB → 150MB | PHP 워커 프로세스 메모리 점유 |
| Network RX | 3.5GB (누적) | Nginx로부터 FastCGI 요청 수신 |
| Network TX | 1GB (누적) | HTML 응답을 Nginx로 전달 |
| I/O Read | 70MB 고정 | WordPress PHP 파일 반복 읽기 |

> **CPU 420% 의미**: 코어 1개 = 100% 기준, 4개 코어 이상 동시 사용. 정상 동작이지만 한계에 근접
> 

**Netdata Apps 기준 프로세스별 CPU 사용량**

| 프로세스 | CPU % | 해석 |
| --- | --- | --- |
| php-fpm | 406.1% | wp_app 핵심 엔진, 코어 4개 풀가동 |
| mysqld | 68.3% | DB 쿼리 처리, 예상보다 높음 |
| dockerd | 55.3% | 컨테이너 관리 데몬 오버헤드 |
| containerd | 38.0% | 컨테이너 런타임 |
| nginx | 10.9% | 요청 수신·전달, 매우 효율적 |
| netdata | 3.4% | 모니터링 수집 비용 |

> **핵심 포인트**: php-fpm 406% vs nginx 10.9% = 비율 약 37:1 → PHP 처리가 압도적 병목
> 

**메모리 사용량 (프로세스별)**

| 프로세스 | 메모리 | 해석 |
| --- | --- | --- |
| mysqld | 414 MiB | DB가 메모리 1위, 버퍼풀 적극 사용 |
| php-fpm | 275 MiB | PHP 워커 프로세스 합산 |
| dockerd | 143 MiB | 컨테이너 관리 오버헤드 |
| netdata | 122 MiB | 모니터링 도구 자체 비용 |
| nginx | 75 MiB | 가장 가벼운 웹서버 확인 |

> **핵심**: DB가 메모리를 가장 많이 쓰는 이유 = MySQL 버퍼풀의 쿼리 캐시를 메모리 할당. nginx는 75MB로 전체 웹 요청 처리 → 메모리 효율 매우 높음
> 

**Netdata Nginx 연결 상태 (ab 실행 중)**

| 상태 | 수치 | 의미 |
| --- | --- | --- |
| writing | 50.67 | 응답을 클라이언트에게 전송 중인 연결 |
| idle | 0.33 | 대기 중인 연결 (거의 없음) |
| accepted | 91.0 conns/s | 초당 수락한 연결 수 |
| handled | 91.0 conns/s | 초당 실제 처리한 연결 수 |

---

### 테스트 2: 정적 파일 부하 (이미지 다운로드)

```bash
# WordPress 관리자(wp-admin)에서 이미지 업로드 후 URL 확인
ab -t 30 -c 50 <http://localhost:8080/wp-content/uploads/2026/05/그림파일명> &
```

**wp_nginx (이미지 직접 처리, 네트워크·I/O 급등)**

| 항목 | 수치 | 이전(동적) 비교 |
| --- | --- | --- |
| Memory | 40MB 고정 | 30MB → 소폭 증가 |
| CPU | 160% → 0% 급락 | 이전 9% → 순간 폭발 후 즉시 종료 |
| Network RX | 5GB → 40GB 급등 | 이전 1GB → 40배 증가 |
| Network TX | 거의 0 | 이전과 동일 |
| I/O Write | 30MB | 이전 12MB → 2.5배 증가 |

> **핵심**: 이미지(정적 파일)는 Nginx가 직접 처리 (PHP-FPM 전달 없음). CPU 순간 폭발 후 즉시 종료 패턴. `-t 30`(30초) 동안 40GB 수신 = 초당 약 1.3GB
> 

**wp_app (기본 부하 유지)**

| 항목 | 수치 | 이전(동적) 비교 |
| --- | --- | --- |
| Memory | 180MB 유지 | 이전 150MB → 소폭 증가 |
| CPU | 60~70% 안정적 유지 | 이전 420% → 대폭 감소 |
| Network RX | 1.5GB → 2.5GB | 이전 3.5GB → 감소 |
| I/O Read | 80MB | 이전 70MB → 유사 |

> **핵심**: 이미지 URL도 WordPress 라우팅 처리 필요 → wp_app이 URL 해석 후 경로 반환, 실제 파일 전송은 wp_nginx 담당
> 

**Netdata 네트워크 분석**

| 항목 | 수치 | 해석 |
| --- | --- | --- |
| Total Network Inbound | 44.23 Gbit/s | WSL2 루프백(loopback) 트래픽 포함 (ab → localhost → Docker 내부 통신) |
| Total Network Outbound | 161.8 Mbit/s | Nginx가 이미지 파일을 클라이언트(ab)에 전송 |
| Total Network Errors | 0 | 에러 없음 |
| Total Network Drops | 0 | 패킷 손실 없음 |

> 인바운드 44Gbit/s는 물리 NIC가 아닌 가상 인터페이스 합산값, 실제 외부 트래픽 아님 (정상)
> 

---

### 테스트 결과 종합 비교

| 분석 지점 | 동적 요청 (index.php) | 정적 파일 요청 (이미지 다운로드) |
| --- | --- | --- |
| wp_nginx CPU | 낮음 (7.8%), 단순 전달 역할 | 매우 높음, 디스크 I/O + 네트워크 소켓 파일 전송 전담 |
| wp_app CPU | 매우 높음 (356.2%), PHP-FPM 급증 | 최저치 (0~1%), 요청이 들어와도 즉시 휴식 상태 |
| wp_db CPU | 완만함 (46.2%), SQL 연산 | 0%, DB 커넥션 거의 없음 |
| 시스템 전체 RAM | 변동폭 적음 (안정적) | 이미지 크기·커넥션 수에 따라 고용량 버퍼링 발생 가능 |
| wp_nginx Network | 1GB | 40GB (40배 증가) |
| wp_app Network | 3.5GB | 2.5GB (감소) |

> **결론**: 파일의 요청 타입(동적 vs 정적)에 따라 컨테이너별 부하가 전혀 다르게 나타난다.
>
---
### 실습문제 - 웹 서버 모니터링
<img width="1842" height="825" alt="image (3)" src="https://github.com/user-attachments/assets/c9bdd401-ba76-4ad6-a74e-b77f5aa8c367" />
---
<img width="1572" height="860" alt="image (4)" src="https://github.com/user-attachments/assets/a871fa66-f629-4244-b849-b9094ee95abe" />

**전체 상태: DEGRADED (불량)**

**1. 노드 오프라인 (5시간 55분 데이터 공백)**

- 02:22 ~ 08:17 UTC 동안 Netdata 에이전트가 꺼져 있었음
- WSL2 특성상 Windows 절전/종료 시 같이 꺼지는 현상으로 추정

**2. 디스크 용량 위험 (현재 WARNING 상태)**

- `/mnt/c` (Windows C드라이브): **98.4% 사용 중** → 거의 꽉 찬 상태
- `/var/lib/docker`: **96.4% 사용 중** → Docker 컨테이너 작동 위험

**3. wp_db 컨테이너 불안정**

- 재시작 직후 2분 30초 동안 WARNING↔CLEAR 4번 반복
- MySQL 초기화 중 헬스체크 실패로 추정, 이후 정상화

**권장 조치:**

- `docker system prune -a --volumes` 로 Docker 공간 확보
- Windows C드라이브 용량 정리


