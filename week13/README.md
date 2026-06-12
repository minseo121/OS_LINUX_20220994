# 13주차 - 서버 백업 관리

## 서버 트렌드 이해

### 3-2-1 백업 법칙

실무에서 데이터 보호를 위해 반드시 지켜야 할 원칙

| 숫자 | 의미 |
| --- | --- |
| **3** | 데이터 복사본을 3개 보유 |
| **2** | 서로 다른 2가지 저장 매체에 분리 저장 (예: 로컬 디스크 + 클라우드) |
| **1** | 최소 1개는 완전히 격리된 오프사이트(Off-site)에 보관 |

> 최근에는 **3-2-1-1-0 규칙**으로 확장: 1개는 오프라인(불변성), 복구 검증 오류 0
> 

### 데이터 손실 위협

- 랜섬웨어 감염 → 백업 불변성(Immutable) 필요
- S/W 에러
- 자연재해

### 백업 도구 비교

| 비교 요소 | rsync (전통 방식) | BorgBackup / Restic (모던 방식) |
| --- | --- | --- |
| 중복 제거 | 매번 통째로 복사 또는 하드링크 사용 | 블록(Chunk) 단위 고성능 중복 제거 (용량 60~80% 절감) |
| 보안 | 평문 저장 (별도 암호화 툴 필요) | 클라이언트 사이드 AES-256 암호화 기본 제공 |
| 랜섬웨어 대응 | 원본 감염 시 백업본도 덮어써짐 | 불변성(Immutable) 및 스냅샷 방식으로 보호 |

### 백업 종류 비교

| 종류 | 방식 | 백업 속도 | 복구 속도 | 저장 공간 |
| --- | --- | --- | --- | --- |
| 전체 백업(Full) | 매번 모든 데이터 복사 | 느림 | 가장 빠름 | 가장 많음 |
| 증분 백업(Incremental) | 직전 백업 이후 변경분만 복사 | 가장 빠름 | 느림 (전체+모든 증분 필요) | 가장 적음 |
| 차분 백업(Differential) | 마지막 전체 백업 이후 누적 변경분 복사 | 보통 | 보통 (전체+마지막 차분 필요) | 중간 |

> Restic은 기본적으로 **증분 백업** 방식 사용
> 

---

### Restic 소개 및 활용

### Restic의 주요 특징

- **암호화**: AES-256 기본 적용
- **중복 제거**: 동일한 데이터 블록을 중복 저장하지 않음
- **증분 백업**: 변경된 부분만 저장
- **무결성 검증**: 백업 데이터 자동 검사 기능

### 주요 명령어

| 명령어 | 용도 |
| --- | --- |
| `restic init` | 저장소 초기화 (최초 1회) |
| `restic backup` | 백업 수행 → 스냅샷 생성 |
| `restic restore` | 스냅샷으로 복구 |
| `restic snapshots` | 스냅샷 목록 조회 |
| `restic diff` | 두 스냅샷 간 차이 비교 |
| `restic forget` | 오래된 스냅샷 삭제 |
| `restic prune` | 불필요한 데이터 정리 |
| `restic check` | 저장소 무결성 검사 |
| `restic stats` | 저장소 통계 확인 |
| `restic unlock` | 잠금 해제 |

---

### STEP 1. 폴더 구조 준비

`# week13 폴더로 이동
cd ~/week13

# 백업 저장 디렉토리 생성
mkdir -p ~/week13/backup/db      # mysqldump 덤프 파일 저장
mkdir -p ~/week13/backup/files   # tar 백업 파일 저장
mkdir -p ~/week13/restore        # 복구된 파일 임시 저장`

| 폴더 | 용도 | 생성 주체 |
| --- | --- | --- |
| `~/week13/restic-repo/` | Restic 저장소 (암호화된 백업 데이터) | `restic init` 자동 생성 |
| `~/week13/backup/db/` | mysqldump 덤프 파일 | 직접 생성 |
| `~/week13/backup/files/` | tar 백업 파일 | 직접 생성 |
| `~/week13/restore/` | 복구된 파일 임시 저장 | `restic restore` 시 사용 |

---

### STEP 2. Restic 설치 및 저장소 초기화

`# 설치
sudo apt install restic -y
which restic        # 설치 경로 확인
restic version      # 버전 확인

# 저장소 디렉토리 생성
mkdir -p ~/week13/restic-repo

# 저장소 초기화 (패스워드 설정 필요 - 입력 시 화면에 안 보임)
restic init --repo ~/week13/restic-repo
# 패스워드 입력: backup2026!`

> ⚠️ 패스워드를 잊어버리면 백업 데이터를 영구적으로 복구할 수 없음! 반드시 기록해 둘 것.
> 

초기화 후 저장소 내부 구조:

`~/week13/restic-repo/
├── config       ← 이 저장소의 설정
├── data/        ← 실제 백업 데이터
├── index/       ← Blob 색인
├── keys/        ← 암호화 키
├── locks/       ← 잠금 파일
└── snapshots/   ← 스냅샷 메타데이터`

---

### STEP 3. WordPress 볼륨 백업

**현재 Docker 볼륨 확인:**

`# WordPress 볼륨 상세 정보 확인
docker volume inspect wordpress_wp_data

# 볼륨 내 파일 목록 확인
sudo ls -lh /var/lib/docker/volumes/wordpress_wp_data/_data/

# 볼륨 총 용량 확인
sudo du -sh /var/lib/docker/volumes/wordpress_wp_data/_data/`

| 구분 | 볼륨 이름 | 호스트 경로 | 컨테이너 경로 |
| --- | --- | --- | --- |
| WordPress | `wordpress_wp_data` | `/var/lib/docker/volumes/wordpress_wp_data/_data` | `/var/www/html` |
| MySQL | — | `/mnt/mysql_data` | `/var/lib/mysql` |

**WordPress 파일 백업 실행:**

`sudo restic -r ~/week13/restic-repo backup \
  /var/lib/docker/volumes/wordpress_wp_data/_data \
  --tag wp_files \
  --tag week13
# 패스워드 입력: backup2026!`

- `-tag`: 스냅샷에 태그를 붙여서 나중에 필터링할 때 사용
- 처음 실행 시 전체 백업, 이후 실행 시 변경분만 백업(증분)

**스냅샷 목록 및 용량 확인:**

`# 스냅샷 목록 확인
sudo restic -r ~/week13/restic-repo snapshots

# 저장소 통계 확인
sudo restic -r ~/week13/restic-repo stats`

---

### STEP 4. 증분 백업 효과 확인

WordPress 관리자 페이지(`https://localhost:8443/wp-admin`)에서 글 작성 및 미디어 파일 업로드 후 다시 백업

`sudo restic -r ~/week13/restic-repo backup \
  /var/lib/docker/volumes/wordpress_wp_data/_data \
  --tag wp_files`

결과 예시:

`Files:  1 new,  0 changed,  3436 unmodified
Dirs:   0 new, 10 changed,   361 unmodified
Added to the repository: 32.042 KiB (17.721 KiB stored)`

→ 변경된 파일만 저장 → 저장 용량이 훨씬 적음

---

### STEP 5. MySQL DB 백업 + Restic 연계

> ⚠️ DB는 실행 중인 파일을 직접 복사하면 안 됨! 트랜잭션 처리 중인 데이터가 불일치 상태로 저장될 수 있음. 반드시 `mysqldump` 사용.
> 

**현재 DB 데이터 확인:**

`docker exec wp_db mysql \
  -u wpuser -pwppass_2026! wordpress \
  -e "SELECT COUNT(*) FROM wp_posts;"`

**DB 덤프 (SQL 파일로 추출 + gzip 압축):**

`docker exec wp_db mysqldump \
  --no-tablespaces \
  -u wpuser -pwppass_2026! wordpress \
  | gzip \
  > ~/week13/backup/db/db_$(date +%F).sql.gz`

- `-no-tablespaces`: 테이블스페이스 권한 없어도 실행 가능
- `$(date +%F)`: 오늘 날짜를 파일명에 자동 삽입 (예: `db_2026-05-31.sql.gz`)
- `gzip`: 압축해서 저장

**압축 파일 내용 확인 (테이블 목록):**

`gunzip -c ~/week13/backup/db/db_$(date +%F).sql.gz | grep "^CREATE TABLE"`

**덤프 파일을 Restic으로 백업:**

`sudo restic -r ~/week13/restic-repo backup \
  ~/week13/backup/db/ \
  --tag db_backup \
  --tag $(date +%F)`

**전체 스냅샷 목록 확인:**

`sudo restic -r ~/week13/restic-repo snapshots`

---

### STEP 6. 백업 검증

**두 스냅샷 비교 (증분 변화 확인):**

`sudo restic -r ~/week13/restic-repo diff 스냅샷ID1 스냅샷ID2`

결과 항목 설명:

| 항목 | 의미 |
| --- | --- |
| Files new/removed/changed | 파일 추가/삭제/변경 수 |
| Data Blobs | 실제 데이터 블록 변화 |
| Tree Blobs | 디렉토리 구조 변화 |

**저장소 무결성 검사:**

`sudo restic -r ~/week13/restic-repo check
# "no errors were found" 출력되면 정상`

---

### STEP 7. 복구 실습 (장애 시뮬레이션)

**현재 상태 확인:**

`docker exec wp_db mysql \
  -u wpuser -pwppass_2026! wordpress \
  -e "SELECT COUNT(*) FROM wp_posts;"
# 현재 게시글 수 확인 (예: 11개)`

**의도적으로 게시글 전체 삭제 (장애 시뮬레이션)**

`docker exec wp_db mysql \
  -u wpuser -pwppass_2026! wordpress \
  -e "DELETE FROM wp_posts;"`

브라우저에서 `https://localhost:8443` 접속 → 게시글 없음 확인

**복구 실행:**

`# 1. DB 백업 스냅샷 ID 확인
sudo restic -r ~/week13/restic-repo snapshots --tag db_backup

# 2. 스냅샷에서 파일 추출 (restore/폴더로)
sudo restic -r ~/week13/restic-repo restore 스냅샷ID --target ~/week13/restore/

# 3. 추출된 덤프 파일 위치로 이동
cd ~/week13/backup/db

# 4. 덤프 파일을 DB에 복원
sudo gunzip -c db_2026-05-31.sql.gz | docker exec -i wp_db mysql -u wpuser -pwppass_2026! wordpress`

**복구 확인:**

`docker exec wp_db mysql \
  -u wpuser -pwppass_2026! wordpress \
  -e "SELECT COUNT(*) FROM wp_posts;"
# 복구 전과 동일한 게시글 수 출력 확인`

브라우저에서 `https://localhost:8443` 재접속 → 게시글 복구 확인

---

### WordPress 백업 플러그인 (UpdraftPlus)

### 설치 방법

1. `https://localhost:8443/wp-admin` 접속
2. 메뉴 → 플러그인 → 플러그인 추가하기
3. "백업"으로 검색
4. **UpdraftPlus: WP 백업 & 마이그레이션 플러그인** → 설치 후 활성화

### 사용 방법

1. 플러그인 → UpdraftPlus 설정 → **지금 백업** 클릭
2. 잠시 대기 후 기존 백업 항목에 표시됨
3. 각 항목(데이터베이스, 플러그인, 테마, 업로드) 클릭 시 다운로드 가능

**실제 저장 위치:**

`sudo ls -lh /var/lib/docker/volumes/wordpress_wp_data/_data/wp-content/updraft/`

**백업 파일 구성:**

| 파일명 | 크기 | 내용 |
| --- | --- | --- |
| `backup_...db.gz` | ~291K | MySQL DB 덤프 (압축) |
| `backup_...others.zip` | ~1.5M | wp-config.php 등 기타 파일 |
| `backup_...plugins.zip` | ~7.8M | 설치된 플러그인 전체 |
| `backup_...themes.zip` | ~13M | 설치된 테마 전체 |
| `backup_...uploads.zip` | ~2.8M | 미디어 업로드 파일 |

---

### CLI 백업 vs UpdraftPlus 비교

| 항목 | CLI 백업 (Restic + mysqldump) | UpdraftPlus |
| --- | --- | --- |
| 백업 방식 | 터미널 명령어 | WordPress 관리자 GUI |
| 백업 위치 | 외부 (`~/week13/restic-repo/`) | 내부 (`wp-content/updraft/`) |
| 볼륨 장애 시 | ✅ 안전 (외부 저장) | ❌ 백업도 함께 소멸 |
| 암호화 | ✅ AES-256 기본 적용 | ❌ 없음 (zip/gz 압축만) |
| 중복 제거 | ✅ 있음 | ❌ 없음 |
| 증분 백업 | ✅ 영구 증분 | ❌ 매번 전체 |
| DB 백업 | mysqldump 별도 실행 필요 | ✅ 자동 포함 |
| 무결성 검사 | ✅ `restic check` | ❌ 없음 |
| 복구 난이도 | 높음 (경로/명령어 필요) | 낮음 (GUI 원클릭) |
| 실무 사용 대상 | 서버 관리자 | WordPress 관리자 |
