# 🍀 four-leaf-infra

> **Four-Leaf** 프로젝트의 인프라 & CD(Continuous Deployment) 레포지토리입니다.  
> 각 서비스 레포에서 CI(빌드/테스트/린트) 통과 후 `main` 브랜치에 push가 발생하면  
> 자동으로 AWS ECR에 이미지를 push하고 EC2 서버에 배포됩니다.

---

## 📋 목차

- [아키텍처](#-아키텍처)
- [레포지토리 구조](#-레포지토리-구조)
- [서비스 포트](#-서비스-포트)
- [사전 준비](#-사전-준비)
- [GitHub Secrets 설정](#-github-secrets-설정-최초-1회)
- [각 서비스 레포 설정](#-각-서비스-레포-설정)
- [CI/CD 흐름](#-cicd-흐름)
- [수동 배포](#-수동-배포)
- [로컬 개발 환경](#-로컬-개발-환경)
- [롤백](#-롤백)
- [트러블슈팅](#-트러블슈팅)

---

## 🏗 아키텍처

```
[GitHub Organization: CapstoneDesignProject1-team9]

 four-laef-frontend  (React/Vite)
   └── push to main
         ├── CI: npm build + lint                     ← ci.yml
         └── CD trigger: ECR push → dispatch ─────────────────┐
                                                                │ repository_dispatch
 four-leaf-backend  (Spring Boot)                              │
   └── push to main                                            │
         ├── CI: Gradle build + test                 ← ci.yml  │
         └── CD trigger: ECR push → dispatch ─────────────────►│
                                                                │
 four-leaf-AI  (Python/LangChain)                              │
   └── push to main                                            │
         ├── CI: ruff lint + pytest                  ← ci.yml  │
         └── CD trigger: ECR push → dispatch ─────────────────►│
                                                                ▼
                                                    [four-leaf-infra]
                                                    deploy-*.yml
                                                    EC2 SSH → docker compose up
```

```
EC2 Server
┌──────────────────────────────────────┐
│  Nginx (80 / 443)                    │
│   ├── /        → Frontend  :3000     │
│   ├── /api/    → Backend   :8080     │
│   └── /ai/     → AI        :8000     │
│                                      │
│  PostgreSQL :5432 (내부 전용)         │
│  Redis      :6379 (내부 전용)         │
└──────────────────────────────────────┘
```

---

## 📁 레포지토리 구조

```
four-leaf-infra/
├── .github/
│   └── workflows/
│       ├── deploy-frontend.yml   # Frontend CD (repository_dispatch 수신)
│       ├── deploy-backend.yml    # Backend CD (repository_dispatch 수신)
│       ├── deploy-ai.yml         # AI CD (repository_dispatch 수신)
│       └── deploy-all.yml        # 전체 스택 수동 배포
├── docker/
│   ├── nginx/
│   │   ├── nginx.conf            # 프로덕션 Nginx 설정 (HTTPS)
│   │   └── nginx.dev.conf        # 개발용 Nginx 설정 (HTTP)
│   └── postgres/
│       └── init.sql              # DB 초기화 SQL
├── scripts/
│   ├── deploy.sh                 # 배포 실행 스크립트
│   ├── rollback.sh               # 롤백 스크립트
│   └── health-check.sh           # 헬스체크 스크립트
├── service-repos/                # 각 서비스 레포에 복사할 워크플로우 템플릿
│   ├── frontend-trigger.yml      → four-laef-frontend: .github/workflows/trigger-cd.yml
│   ├── backend-trigger.yml       → four-leaf-backend:  .github/workflows/trigger-cd.yml
│   └── ai-trigger.yml            → four-leaf-AI:       .github/workflows/trigger-cd.yml
├── docker-compose.yml            # 프로덕션 전체 스택
├── docker-compose.dev.yml        # 로컬 개발용
└── .env.example                  # 환경변수 템플릿
```

---

## 🔌 서비스 포트

| 서비스 | 컨테이너 내부 포트 | 외부 접근 경로 |
|--------|:-----------------:|---------------|
| Nginx | 80 / 443 | Public |
| Frontend (React/Vite) | 3000 | `https://your-domain/` |
| Backend (Spring Boot) | 8080 | `https://your-domain/api/` |
| AI (Python/LangChain) | 8000 | `https://your-domain/ai/` |
| PostgreSQL | 5432 | 내부 전용 |
| Redis | 6379 | 내부 전용 |

---

## 🛠 사전 준비

### EC2 서버 초기 설정 (최초 1회)

```bash
# 1. Docker & Docker Compose 설치
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# 2. AWS CLI 설치
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# 3. AWS 자격증명 설정
#    IAM 역할 사용 시: EC2 인스턴스에 ECR 읽기 권한 역할 부여 (권장)
#    직접 설정 시:
aws configure

# 4. infra 레포 clone
git clone https://github.com/CapstoneDesignProject1-team9/four-leaf-infra.git ~/four-leaf-infra
cd ~/four-leaf-infra

# 5. 환경변수 파일 설정
cp .env.example .env
nano .env   # 실제 값 입력
```

### AWS ECR 레포지토리 생성 (최초 1회)

```bash
aws ecr create-repository --repository-name four-leaf-frontend --region ap-northeast-2
aws ecr create-repository --repository-name four-leaf-backend  --region ap-northeast-2
aws ecr create-repository --repository-name four-leaf-ai       --region ap-northeast-2
```

---

## 🔐 GitHub Secrets 설정 (최초 1회)

### `four-leaf-infra` 레포 Secrets

**Settings → Secrets and variables → Actions → New repository secret**

| Secret 이름 | 값 예시 | 설명 |
|------------|---------|------|
| `DEPLOY_HOST` | `13.125.xxx.xxx` | EC2 퍼블릭 IP 또는 도메인 |
| `DEPLOY_USER` | `ubuntu` | SSH 접속 유저명 |
| `DEPLOY_SSH_KEY` | `-----BEGIN OPENSSH...` | SSH private key 전체 내용 |
| `DEPLOY_PORT` | `22` | SSH 포트 |
| `AWS_ACCESS_KEY_ID` | `AKIA...` | IAM Access Key ID |
| `AWS_SECRET_ACCESS_KEY` | `...` | IAM Secret Access Key |
| `MAIL_SERVER` | `smtp.gmail.com` | SMTP 서버 |
| `MAIL_PORT` | `587` | SMTP 포트 |
| `MAIL_USERNAME` | `noreply@example.com` | 발신 이메일 |
| `MAIL_PASSWORD` | `앱 비밀번호` | Gmail 앱 비밀번호 |
| `NOTIFY_EMAIL` | `team@example.com` | 수신 이메일 |

> **SSH 키 생성:**
> ```bash
> ssh-keygen -t ed25519 -C "four-leaf-deploy" -f ~/.ssh/four-leaf-deploy
> # 공개키를 EC2에 등록
> cat ~/.ssh/four-leaf-deploy.pub >> ~/.ssh/authorized_keys   # (EC2에서 실행)
> # 비밀키를 DEPLOY_SSH_KEY Secret에 등록
> cat ~/.ssh/four-leaf-deploy   # 이 내용 전체를 복사
> ```

> **Gmail 앱 비밀번호:** [Google 계정](https://myaccount.google.com) → 보안 → 2단계 인증 → 앱 비밀번호

---

### `four-laef-frontend` 레포 Secrets

| Secret 이름 | 설명 |
|------------|------|
| `AWS_ACCESS_KEY_ID` | IAM Key (ECR push 권한) |
| `AWS_SECRET_ACCESS_KEY` | IAM Secret |
| `INFRA_DISPATCH_TOKEN` | infra 레포에 `repo` 권한 있는 PAT |

### `four-leaf-backend` 레포 Secrets

| Secret 이름 | 설명 |
|------------|------|
| `AWS_ACCESS_KEY_ID` | IAM Key |
| `AWS_SECRET_ACCESS_KEY` | IAM Secret |
| `INFRA_DISPATCH_TOKEN` | 동일한 PAT |

### `four-leaf-AI` 레포 Secrets

| Secret 이름 | 설명 |
|------------|------|
| `AWS_ACCESS_KEY_ID` | IAM Key |
| `AWS_SECRET_ACCESS_KEY` | IAM Secret |
| `INFRA_DISPATCH_TOKEN` | 동일한 PAT |

> **INFRA_DISPATCH_TOKEN 발급:**  
> GitHub → Settings → Developer settings → Personal access tokens (classic)  
> → `repo` 스코프 선택 → 생성 후 3개 서비스 레포에 모두 등록

---

## ⚙️ 각 서비스 레포 설정 (최초 1회)

각 서비스 레포에는 이미 다음 두 워크플로우 파일이 포함되어 있어야 합니다:

| 파일 | 역할 |
|------|------|
| `.github/workflows/ci.yml` | PR/push 시 CI (빌드, 테스트, 린트) |
| `.github/workflows/trigger-cd.yml` | main push 시 CI → ECR push → infra dispatch |

> 이미 생성되어 있습니다. Secrets만 등록하면 바로 동작합니다.

---

## 🔄 CI/CD 흐름

```
1. 개발자가 PR 생성 / main push
         │
         ▼
2. ci.yml 실행 (PR + push 모두)
   Frontend: npm ci → lint → build
   Backend:  Gradle build → test
   AI:       pip install → ruff → pytest
         │
   ✅ CI 통과 + main branch인 경우만
         │
         ▼
3. trigger-cd.yml 실행 (needs: ci)
   - Docker image build
   - AWS ECR push (SHA tag + latest)
   - repository_dispatch → four-leaf-infra
         │
         ▼
4. four-leaf-infra deploy-*.yml 실행
   - EC2 SSH 접속
   - ECR 이미지 pull
   - .env 파일 IMAGE 주소 업데이트 (sed, 원자적)
   - docker compose up -d --no-deps
   - health-check.sh 실행
         │
         ├─ 성공 → 팀에 성공 이메일 ✅
         └─ 실패 → 팀에 실패 이메일 ❌ (로그 링크 포함)
```

---

## 🚀 수동 배포

GitHub Actions UI에서 수동으로 배포할 수 있습니다.

### 특정 서비스만 재배포

1. `Actions` 탭 → `Deploy Frontend` / `Deploy Backend` / `Deploy AI` 선택
2. `Run workflow` 버튼 클릭
3. image tag 입력 (기본값: `latest`, 또는 특정 commit SHA)

### 전체 스택 재배포

1. `Actions` 탭 → `Deploy All Services` 선택
2. `Run workflow` 버튼 클릭
3. 각 서비스의 image tag 입력

---

## 💻 로컬 개발 환경

```bash
# 1. 환경변수 파일 생성
cp .env.example .env.dev
nano .env.dev   # 개발용 값으로 수정

# 2. 전체 스택 실행
docker compose -f docker-compose.dev.yml up -d

# 3. 로그 확인
docker compose -f docker-compose.dev.yml logs -f

# 4. 특정 서비스 로그
docker compose -f docker-compose.dev.yml logs -f backend

# 5. 종료
docker compose -f docker-compose.dev.yml down
```

접속: `http://localhost`

---

## ⏪ 롤백

### GitHub Actions UI에서 롤백 (권장)

1. `Actions` 탭 → `Deploy Frontend` (또는 Backend/AI)
2. `Run workflow` → 이전 commit SHA 입력

### EC2 서버에서 긴급 롤백

```bash
cd ~/four-leaf-infra

# 이전 이미지 태그 확인 (ECR 콘솔 또는)
aws ecr list-images --repository-name four-leaf-frontend --region ap-northeast-2

# 롤백 스크립트 사용
bash scripts/rollback.sh frontend <이전-SHA>
bash scripts/rollback.sh backend  <이전-SHA>
bash scripts/rollback.sh ai       <이전-SHA>
```

---

## 🔧 트러블슈팅

### ECR 로그인 실패 (EC2에서)

```bash
# AWS CLI 자격증명 확인
aws sts get-caller-identity

# ECR 로그인 테스트
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-northeast-2.amazonaws.com
```

### 컨테이너가 시작 안 될 때

```bash
docker compose logs frontend   # 서비스별 로그
docker compose logs backend
docker compose logs ai
docker compose ps              # 컨테이너 상태
```

### 헬스체크 실패

```bash
# 서비스별 직접 확인
curl http://localhost:3000              # Frontend
curl http://localhost:8080/actuator/health  # Backend
curl http://localhost:8000/health      # AI
```

### repository_dispatch 가 안 오는 경우

1. 서비스 레포의 `INFRA_DISPATCH_TOKEN` Secret 확인 (만료 여부)
2. PAT의 `repo` 스코프 확인
3. `trigger-cd.yml`의 `repository:` 값이 `CapstoneDesignProject1-team9/four-leaf-infra` 인지 확인
4. 서비스 레포 Actions 탭에서 `trigger-cd.yml` 워크플로우 실행 로그 확인

### Nginx 설정 문제

```bash
docker compose exec nginx nginx -t        # 설정 문법 검사
docker compose exec nginx nginx -s reload  # 설정 리로드
```

---

## 📌 GitHub Secrets 한눈에 보기

| Secret | infra | frontend | backend | AI | 설명 |
|--------|:-----:|:--------:|:-------:|:--:|------|
| `DEPLOY_HOST` | ✅ | | | | EC2 IP |
| `DEPLOY_USER` | ✅ | | | | SSH 유저 |
| `DEPLOY_SSH_KEY` | ✅ | | | | SSH private key |
| `DEPLOY_PORT` | ✅ | | | | SSH 포트 |
| `AWS_ACCESS_KEY_ID` | ✅ | ✅ | ✅ | ✅ | IAM Key |
| `AWS_SECRET_ACCESS_KEY` | ✅ | ✅ | ✅ | ✅ | IAM Secret |
| `MAIL_SERVER` | ✅ | | | | SMTP 서버 |
| `MAIL_PORT` | ✅ | | | | SMTP 포트 |
| `MAIL_USERNAME` | ✅ | | | | 발신 메일 |
| `MAIL_PASSWORD` | ✅ | | | | 메일 비밀번호 |
| `NOTIFY_EMAIL` | ✅ | | | | 수신 메일 |
| `INFRA_DISPATCH_TOKEN` | | ✅ | ✅ | ✅ | infra repo PAT |