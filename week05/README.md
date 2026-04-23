# 5주차 - 프로세스 관리 1

## 서버 트렌드 이해

**프로세스란?**
S/W가 메모리 위에서 실행되고 있는 상태.
프로그램은 디스크에 저장된 파일. 그걸 실행하면 메모리에 올라가서 돌아가는 상태가 프로세스.
ex) 카톡 앱 파일 = 프로그램 / 카톡 켜서 실행중인 상태 = 프로세스

**리눅스 vs 윈도우**
- 리눅스 : fork()로 기존 프로세스를 복제해서 자식을 만드는 방식. 트리 구조.
- 윈도우 : CreateProcess()로 아예 새로 만듬.
- 서버 OS로 리눅스가 유리한 이유 : 프로세스 중심이라 대규모 처리 가능하고 메모리를 적게 씀.

**NPTL(Native POSIX Thread Library)**
리눅스 스레드 관리 방식. 스레드 = 프로세스 안에서 실제로 일을 처리하는 단위.
NPTL 이전에는 스레드가 많아지면 성능이 급격히 떨어졌는데, 2003년 이후 1:1 매핑 방식으로 바뀌면서 커널이 직접 관리. 수만개 스레드도 효율적으로 처리 가능.

---

## 프로세스 확인 및 제어

```bash
docker ps   # 컨테이너 확인 (1개는 compose, 1개는 기본 docker로 실행됨)

ps -ef      # 전체 프로세스 목록
ps -aux     # 전체 + CPU/메모리 사용량

pstree -p                      # 트리구조로 전체 프로세스 확인
pstree -p $(pgrep dockerd)     # docker 프로세스만 트리구조로 확인

sudo ss -lnp | grep -E '포트번호'   # docker-proxy 포트 확인
pstree -p | grep nginx              # nginx 부모 프로세스 확인
docker exec 컨테이너id ps -ef       # 컨테이너 내부 프로세스 확인
```

- docker 컨테이너 1개당 docker-proxy 2개씩 활성화 (IPv4, IPv6 각각)
- 컨테이너 내부에서 ps -ef 치면 PID가 1번부터 시작 (격리된 공간이라 독립적인 시스템처럼 보임)

**프로세스 종류**
- 포그라운드 : 터미널에서 직접 실행. Ctrl+C로 종료.
- 백그라운드 : 터미널에 연결은 돼있는데 뒤에서 돌아감. 명령어 뒤에 & 붙이면 됨.
- 데몬 : 터미널 연결 없음. 부모가 init(1번). sshd, dockerd 등.
- 서비스 : 데몬을 관리하는 단위. systemctl 명령어로 제어. 윈도우 서비스랑 비슷.

```bash
ps -ef | grep docker    # docker 관련 프로세스 확인
ps -ef | grep nginx     # nginx 관련 프로세스 확인
nproc                   # 논리 코어 개수 확인
lscpu                   # CPU 상세 정보 확인
```

top : 리눅스 내장. htop : 따로 설치. 색깔, 마우스, 트리구조 지원.

**프로세스 상태**
- S(Sleeping) : 대기중 - 정상
- R(Running) : CPU 사용중 - 정상
- Z(Zombie) : 종료됐는데 회수 안 함 - 비정상
- D : 디스크 I/O 대기 - 위험신호

**좀비 프로세스란?**
부모가 fork()로 자식을 만들고 wait()를 호출하지 않으면, 자식이 종료돼도 커널이 PID를 계속 점유. 실제 메모리는 해제되지만 PID는 남아있는 상태.

**좀비 없애는 방법**

```bash
# 1. 포그라운드/백그라운드 제어로 부모 종료
jobs -l          # 백그라운드 작업 목록
kill -STOP %1    # 일시정지
bg %1            # 백그라운드 다시 실행
fg %1            # 포그라운드로 가져와서 Ctrl+C로 종료
# 부모가 죽으면 init이 좀비 자식 수거

# 2. 이름으로 종료
pkill -f zombie || true

# 3. 외부에서 강제 종료
docker exec stress-nginx kill -9 pid
# 15번 = 정상 종료 / 9번 = 강제 종료
```

---

## 모니터링을 위한 부하 분석

**평균 부하 분석**
주요 부하 원인 : CPU, 메모리, I/O

```bash
uptime      # 전체 부하 확인 (1분, 5분, 15분 평균)
top         # CPU 확인. 대부분 0.0%
```

**Docker 컨테이너 분석**

```bash
docker top stress-nginx -o pid,ppid,pcpu,comm   # 프로세스 부하 확인
docker exec stress-nginx top                     # 컨테이너 내부 확인
docker stats                                     # 현재 docker 전체 상태 확인
```

docker 내부 worker는 대부분 S(대기) 상태. 자원 소모 적음.

**부하 테스트**

```bash
apk add stress-ng
stress-ng --cpu 8 --timeout 60s &                              # 백그라운드 부하 실행
watch -n 1 docker top stress-nginx -o pid,ppid,pcpu,comm       # 1초마다 확인
docker stats                                                    # 전체 상태 확인
```

컨테이너 내부 top으로 보면 컨테이너 자신을 100% 기준으로 봄.
외부 docker stats는 호스트 전체 CPU 기준이라 다르게 나옴.
⇒ 컨테이너 모니터링은 내부 top보다 외부 docker stats, docker top이 정확함.

---

## 기본 실습 문제

**Docker 내부 워커 프로세스 제한**

```bash
docker exec -it stress-nginx sh        # 컨테이너 접속
vi /etc/nginx/nginx.conf               # worker_processes auto → worker_processes 2 로 수정
docker restart stress-nginx            # 재시작
docker top stress-nginx -o pid,ppid,comm   # 워커 개수 확인
```

결과 : 마스터 1개 + 워커 2개 확인

**워커 프로세스 부하 전후 확인**

부하 전
stress-nginx   CPU 0.00%   MEM 3.152MiB / 7.459GiB
부하 후
```bash
stress-ng --cpu 2 --cpu-method rand --timeout 30s --metrics &
```
stress-nginx   CPU 96.73%   MEM 21.41MiB / 7.459GiB
논리 코어 16개 기준, 워커 2개 풀로드 = 200/16 = 약 12.5% 가 이론값이나
WSL 환경 특성상 다르게 측정될 수 있음.
