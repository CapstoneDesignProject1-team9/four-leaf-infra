#!/usr/bin/env bash
# =============================================================
# rollback.sh — 이전 버전으로 롤백하는 스크립트
# 사용법:
#   bash scripts/rollback.sh frontend <이전-image-tag>
#   bash scripts/rollback.sh backend  <이전-image-tag>
#   bash scripts/rollback.sh ai       <이전-image-tag>
#
# 예시:
#   bash scripts/rollback.sh frontend abc1234
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

SERVICE="$1"
ROLLBACK_TAG="$2"

if [ -z "$SERVICE" ] || [ -z "$ROLLBACK_TAG" ]; then
    log_error "인자가 부족합니다."
    echo "사용법: $0 [frontend|backend|ai] <rollback-image-tag>"
    echo "예시:   $0 frontend abc1234def567"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"

cd "$INFRA_DIR"

# ECR URI 확인
if [ -f ".env.deploy" ]; then
    source .env.deploy
fi

# ─────────────────────────────────────────
# 롤백 함수
# ─────────────────────────────────────────
rollback_service() {
    local name=$1
    local tag=$2

    log_step "${name} 롤백 시작 → 태그: ${tag}"

    # 현재 실행 중인 이미지 백업 기록
    CURRENT=$(docker compose images "$name" --format "{{.Image}}" 2>/dev/null || echo "unknown")
    log_info "현재 이미지: ${CURRENT}"
    log_info "롤백 대상:   ${tag}"

    # 이미지가 로컬에 없으면 pull
    if ! docker image inspect "$tag" > /dev/null 2>&1; then
        log_info "이미지가 로컬에 없습니다. Pull 시도 중..."
        docker pull "$tag"
    fi

    # 서비스 재시작
    case "$name" in
        frontend) export FRONTEND_IMAGE="$tag" ;;
        backend)  export BACKEND_IMAGE="$tag"  ;;
        ai)       export AI_IMAGE="$tag"       ;;
    esac

    docker compose up -d --no-deps "$name"

    log_success "${name} 롤백 완료 ✅"
}

# ─────────────────────────────────────────
# 실행
# ─────────────────────────────────────────
echo "⚠️  롤백을 시작합니다."
echo "   서비스: ${SERVICE}"
echo "   태그:   ${ROLLBACK_TAG}"
echo ""
read -p "계속하시겠습니까? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log_info "롤백이 취소되었습니다."
    exit 0
fi

case "$SERVICE" in
    frontend|backend|ai)
        rollback_service "$SERVICE" "$ROLLBACK_TAG"
        bash "$SCRIPT_DIR/health-check.sh" "$SERVICE"
        ;;
    *)
        log_error "알 수 없는 서비스: ${SERVICE}"
        echo "사용법: $0 [frontend|backend|ai] <rollback-image-tag>"
        exit 1
        ;;
esac

log_success "롤백 완료 🎉"
