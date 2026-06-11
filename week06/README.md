# 6주차 - 프로세스 관리 2

## 1. 서버 트렌드 이해

### 프로세스 스케줄링이란?
CPU 코어가 1개면 동시에 딱 1개의 프로세스만 진행 가능 → CPU는 한정된 자원  
프로세스는 수십~수백 개가 동시에 존재하기 때문에 CPU를 언제, 얼마나 쓸지 결정하기 위해 프로세스 스케줄링이 필요함.  
> 즉, 프로세스 스케줄러는 CPU 시간을 배분한다.

### 리눅스 스케줄러 특징
- **다수 프로세스 처리** → 순서와 시간 제어
  - `Running` : 현재 CPU에서 실행 중
  - `Ready` : CPU 받을 준비 완료, 줄 서 있는 상태
  - `Waiting/Blocked` : I/O 등 기다리는 중 (CPU 줘도 못 씀)
- **컨텍스트 스위칭** : CPU가 프로세스를 교체 (상태는 PCB에 저장)
- **PCB** (Process Control Block) : 컨텍스트 스위칭이 가능한 이유

### 리눅스 스케줄러 종류
| 스케줄러 | 설명 |
|----------|------|
| CFS | 현재 기본 스케줄러. 모든 프로세스에게 공평하게 CPU 시간 배분 |
| Real-Time | 마감 시간이 중요한 작업용 |
| Deadline | 몇 초 안에 반드시 끝내야 하는 작업용 |

---

## 2. 프로세스 최적화 및 제한

### 프로세스 우선순위 확인
낮을수록 우선순위가 높음.

```bash
ps -al     # PRI(기본값 80) / NI(-20~19, 사용자 조정 가능)
top        # PR(기본값 20) / 실제 우선순위 = 20 + NI
```

### Nice를 활용한 우선순위 제어

```bash
nice -n 15 sleep 300 &
ps -al
```

> PRI = 80 + NI(15) = 95 → 우선순위 낮아짐  
> 우선순위를 높이려면 음수값 설정 필요 (root 권한 필요)

### 우선순위 값에 따른 성능 비교

```bash
# 같은 CPU 0번 코어에서 경쟁
docker exec stress-nginx nice -n 0 stress-ng --cpu 1 --timeout 60 &
docker exec stress-nginx nice -n 10 stress-ng --cpu 1 --timeout 60 &
```

```
2123   0  86.5 stress-ng-cpu   ← nice 0, CPU 많이 받음
2129  10   9.2 stress-ng-cpu   ← nice 10, CPU 적게 받음
```

> 낮은 nice값이 CPU를 더 많은 비율로 가져감!

### RT 프로세스 확인

```bash
chrt -p $$                                          # 현재 쉘 스케줄링 정책
ps -eo pid,class,rtprio,ni,pri,comm | head -30      # 전체 프로세스 정책
```

> WSL 환경에서는 모두 TS(CFS) → nice 조절이 유효한 환경임을 확인

### 프로세스 제한

nice만으로는 한계가 있음 (프로세스 수백개 생성, 파일 무한정 오픈 등)

**1) 현재 제한 확인**
```bash
ulimit -a     # 거의 다 unlimited
```

**2) 세션 제한 (재시작하면 사라짐)**
```bash
ulimit -u 30
```

**3) 영구 제한 - 특정 사용자**
```bash
sudo nano /etc/security/limits.conf
```
```
student1    soft    nproc    10
student1    hard    nproc    15
student1    soft    nofile   20
student1    hard    nofile   30
```

**4) 영구 제한 - 그룹 (`@` 붙이면 그룹 적용)**
```
@dev_team1    soft    nproc    10
@dev_team1    hard    nproc    15
@dev_team1    soft    nofile   50
```

> 개인 제한 vs 그룹 제한 → **개인 제한이 우선 적용됨**

### Docker 컨테이너 프로세스 제한

```bash
# nginx 프로세스 모니터링
watch -n 1 'docker exec stress-nginx ps -ef | grep nginx'

# 부하 테스트
ab -n 10000 -c 1000 http://localhost:8081/
```

| 구분 | 부하 전 | 부하 중 |
|------|---------|---------|
| worker 개수 | 2개 | 2개 (안 변함) |
| CPU % | 4.70% | 100.04% |

> nginx는 요청이 많아져도 worker를 새로 안 만듦  
> → 프로세스 개수 제한(`--pids-limit`)은 의미 없음  
> → **CPU 점유율 제한(`--cpus`)이 필요!**

---

## 3. 실습문제 1 - Nice 설정에 따른 부하 분석

```bash
docker run -d --name stress-nginx --cpuset-cpus="0" --privileged -p 8081:80 nginx:alpine
docker exec stress-nginx apk add --no-cache stress-ng

# nice 0 vs nice -10 비교 (120초)
docker exec stress-nginx nice -n 0 stress-ng --cpu 1 --timeout 120 &
docker exec stress-nginx nice -n -10 stress-ng --cpu 1 --timeout 120 &
```
<img width="1198" height="170" alt="image" src="https://github.com/user-attachments/assets/e9c13e9f-507d-48ad-b24f-b9d51422257a" />
| PID | NI | CPU% | 의미 |
|-----|----|------|------|
| 41027 | -10 | 85.7% | 우선순위 높음 → CPU 많이 받음 |
| 41033 | 0 | 8.9% | 우선순위 낮음 → CPU 적게 받음 |

---

## 4. 실습문제 2 - Docker CPU 점유율 제한

```bash
# stress-nginx : 코어 0-3 고정, CPU 4코어 제한
docker run -d --name stress-nginx --cpuset-cpus="0-3" --cpus="4.0" -p 8081:80 nginx:alpine

# my-web-proxy : 코어 4-7 고정, CPU 4코어 제한
docker run -d --name my-web-proxy --cpuset-cpus="4-7" --cpus="4.0" -p 80:80 nginx:alpine
```

- 코어 4개 할당 → **nginx worker 4개 자동 생성** (할당 코어 수 = worker 수)
<img width="888" height="240" alt="image (1)" src="https://github.com/user-attachments/assets/a4cef37e-a1b9-4d78-8040-c4549619930b" />

- ab 부하 테스트 결과 : 10,000개 요청, 실패 **0개**, 3,706 req/sec
<img width="726" height="882" alt="image (2)" src="https://github.com/user-attachments/assets/98a2dbf5-4433-490d-93cd-70a853032e16" />
