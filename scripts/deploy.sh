#!/usr/bin/env bash
# =============================================================
# deploy.sh — 서비스 배포 스크립트
# 사용법:
#   bash scripts/deploy.sh frontend <image_tag>
#   bash scripts/deploy.sh backend  <image_tag>
#   bash scripts/deploy.sh ai       <image_tag>
#   bash scripts/deploy.sh all      <tag_for_all>
# =============================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${YELLOW}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${BLUE}[STEP]${NC}  $1"; }

SERVICE="${1:-all}"
TAG="${2:-latest}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

cd "$INFRA_DIR"

# .env.deploy 가 있으면 로드
if [ -f ".env.deploy" ]; then
    source .env.deploy
fi

# ─────────────────────────────────────────
# 배포 함수
# ─────────────────────────────────────────
deploy_service() {
    local name=$1
    local env_var=$2
    local image_tag=$3

    log_step "${name} 배포 시작 (태그: ${image_tag})"

    # 이미지 pull
    log_info "${name} 이미지 pull 중..."
    export "$env_var"="$image_tag"
    docker compose pull "$name"

    # 컨테이너 재시작 (다운타임 최소화)
    log_info "${name} 컨테이너 재시작 중..."
    docker compose up -d --no-deps --remove-orphans "$name"

    # 이전 이미지 정리
    docker image prune -f > /dev/null 2>&1 || true

    log_success "${name} 배포 완료 ✅"
}

# ─────────────────────────────────────────
# 실행
# ─────────────────────────────────────────
log_step "배포 시작: SERVICE=${SERVICE}, TAG=${TAG}"
echo "────────────────────────────────────────"

case "$SERVICE" in
    frontend)
        deploy_service "frontend" "FRONTEND_IMAGE" "${FRONTEND_IMAGE:-$TAG}"
        bash "$SCRIPT_DIR/health-check.sh" frontend
        ;;
    backend)
        deploy_service "backend" "BACKEND_IMAGE" "${BACKEND_IMAGE:-$TAG}"
        bash "$SCRIPT_DIR/health-check.sh" backend
        ;;
    ai)
        deploy_service "ai" "AI_IMAGE" "${AI_IMAGE:-$TAG}"
        bash "$SCRIPT_DIR/health-check.sh" ai
        ;;
    all)
        deploy_service "frontend" "FRONTEND_IMAGE" "${FRONTEND_IMAGE:-$TAG}"
        deploy_service "backend"  "BACKEND_IMAGE"  "${BACKEND_IMAGE:-$TAG}"
        deploy_service "ai"       "AI_IMAGE"       "${AI_IMAGE:-$TAG}"
        sleep 15
        bash "$SCRIPT_DIR/health-check.sh" all
        ;;
    *)
        log_error "알 수 없는 서비스: ${SERVICE}"
        echo "사용법: $0 [frontend|backend|ai|all] [image_tag]"
        exit 1
        ;;
esac

echo "────────────────────────────────────────"
log_success "배포 스크립트 완료 🎉"
