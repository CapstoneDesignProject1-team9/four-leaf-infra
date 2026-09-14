#!/usr/bin/env bash
# =============================================================
# health-check.sh — 컨테이너 헬스체크 스크립트
# 사용법:
#   bash scripts/health-check.sh frontend
#   bash scripts/health-check.sh backend
#   bash scripts/health-check.sh ai
#   bash scripts/health-check.sh all
# =============================================================

set -e

SERVICE="${1:-all}"
MAX_RETRIES=12      # 최대 재시도 횟수
INTERVAL=10         # 재시도 간격 (초)
TIMEOUT=5           # curl 타임아웃 (초)

# 컬러 출력
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${YELLOW}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ─────────────────────────────────────────
# 개별 서비스 헬스체크 함수
# ─────────────────────────────────────────
check_service() {
    local name=$1
    local url=$2
    local retries=0

    log_info "${name} 헬스체크 시작... (최대 $((MAX_RETRIES * INTERVAL))초 대기)"

    while [ $retries -lt $MAX_RETRIES ]; do
        if curl -sf --max-time "$TIMEOUT" "$url" > /dev/null 2>&1; then
            log_success "${name} 헬스체크 통과 ✅"
            return 0
        fi

        retries=$((retries + 1))
        log_info "${name} 응답 없음. 재시도 ${retries}/${MAX_RETRIES} (${INTERVAL}초 후)..."
        sleep "$INTERVAL"
    done

    log_error "${name} 헬스체크 실패 ❌ (${MAX_RETRIES}회 재시도 초과)"
    return 1
}

# ─────────────────────────────────────────
# 서비스별 URL 정의
# ─────────────────────────────────────────
FRONTEND_URL="http://localhost:3000"
BACKEND_URL="http://localhost:8080/actuator/health"
AI_URL="http://localhost:8000/health"

# ─────────────────────────────────────────
# 실행
# ─────────────────────────────────────────
FAILED=0

case "$SERVICE" in
    frontend)
        check_service "Frontend" "$FRONTEND_URL" || FAILED=1
        ;;
    backend)
        check_service "Backend" "$BACKEND_URL" || FAILED=1
        ;;
    ai)
        check_service "AI" "$AI_URL" || FAILED=1
        ;;
    all)
        check_service "Frontend" "$FRONTEND_URL" || FAILED=1
        check_service "Backend"  "$BACKEND_URL"  || FAILED=1
        check_service "AI"       "$AI_URL"       || FAILED=1
        ;;
    *)
        log_error "알 수 없는 서비스: ${SERVICE}"
        echo "사용법: $0 [frontend|backend|ai|all]"
        exit 1
        ;;
esac

if [ $FAILED -ne 0 ]; then
    log_error "하나 이상의 서비스 헬스체크 실패. 배포를 중단합니다."
    exit 1
fi

log_success "모든 헬스체크 통과 🎉"
exit 0
