#!/usr/bin/env bash
# =============================================================================
# YourStockForecast — build.sh
# =============================================================================
# Orchestrates the full pipeline:
#   1. Pre-generate Hugo data files from PostgreSQL
#   2. Run hugo build
#   3. Optionally deploy to VPS via rsync / scp
#   4. Reload Nginx
#
# Usage:
#   ./build.sh                    # full build
#   ./build.sh --dev              # hugo server (hot-reload, no deploy)
#   ./build.sh --data-only        # regenerate data + rebuild, skip deploy
#   ./build.sh --deploy-only      # rsync existing public/ to VPS
#   ./build.sh --pages-only       # regenerate stock page stubs only
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HUGO_SITE="${PROJECT_ROOT}/frontend/hugo-site"
PYTHON="${PYTHON:-python3}"

# ── VPS deployment config ──────────────────────────────────────────────────────
# Override these in a local .env file (git-ignored):
#   VPS_HOST=yourstockforecast.com
#   VPS_USER=deploy
#   VPS_PATH=/var/www/yourstockforecast
#   VPS_NGINX_RELOAD=true
[[ -f "${PROJECT_ROOT}/.env" ]] && source "${PROJECT_ROOT}/.env"
VPS_HOST="${VPS_HOST:-}"
VPS_USER="${VPS_USER:-deploy}"
VPS_PATH="${VPS_PATH:-/var/www/yourstockforecast}"
VPS_NGINX_RELOAD="${VPS_NGINX_RELOAD:-true}"

# ── Colours ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}▶${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
err()     { echo -e "${RED}✗${NC}  $*" >&2; exit 1; }
success() { echo -e "${GREEN}✅${NC}  $*"; }

# ── Arg parsing ────────────────────────────────────────────────────────────────
MODE="full"
[[ "${1:-}" == "--dev"         ]] && MODE="dev"
[[ "${1:-}" == "--data-only"   ]] && MODE="data"
[[ "${1:-}" == "--deploy-only" ]] && MODE="deploy"
[[ "${1:-}" == "--pages-only"  ]] && MODE="pages"

echo "═══════════════════════════════════════════"
echo "  YourStockForecast Build  [mode: $MODE]"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════"

# ── Dev mode: hot-reload Hugo server ──────────────────────────────────────────
if [[ "$MODE" == "dev" ]]; then
    info "Starting Hugo dev server with PostgREST (localhost:3000)…"
    # Override API base to localhost for dev
    sed -i.bak 's|api_base.*=.*|api_base = "http://localhost:3000"|' \
        "${HUGO_SITE}/hugo.toml" 2>/dev/null || true
    cd "${HUGO_SITE}" && hugo server --disableFastRender --bind 0.0.0.0 -p 1313
    exit 0
fi

# ── Step 1: Generate Hugo data from PostgreSQL ─────────────────────────────────
if [[ "$MODE" != "deploy" ]]; then
    info "Step 1/3: Generating Hugo data from PostgreSQL…"
    if command -v python3 &>/dev/null; then
        ARGS=""
        [[ "$MODE" == "pages" ]] && ARGS="--pages-only"
        $PYTHON "${SCRIPT_DIR}/generate_hugo_data.py" $ARGS
        success "Data generation complete."
    else
        warn "python3 not found — skipping data generation (stale data will be used)."
    fi
fi

# ── Step 2: Hugo build ─────────────────────────────────────────────────────────
if [[ "$MODE" != "deploy" ]]; then
    info "Step 2/3: Running hugo build…"
    if ! command -v hugo &>/dev/null; then
        err "hugo not found in PATH. Install: https://gohugo.io/installation/"
    fi

    # Switch to prod API URL if deploying
    if [[ -n "$VPS_HOST" ]] && [[ "$MODE" == "full" ]]; then
        PROD_API="https://api.${VPS_HOST}"
        info "  Setting api_base = ${PROD_API}"
        sed -i.bak "s|api_base.*=.*|api_base = \"${PROD_API}\"|" \
            "${HUGO_SITE}/hugo.toml" 2>/dev/null || true
    fi

    cd "${HUGO_SITE}"
    hugo --minify --gc
    BUILD_SIZE=$(du -sh public 2>/dev/null | cut -f1 || echo "?")
    success "Hugo build complete. Output: public/ (${BUILD_SIZE})"
fi

# ── Step 3: Deploy to VPS ──────────────────────────────────────────────────────
if [[ "$MODE" == "full" ]] || [[ "$MODE" == "deploy" ]]; then
    if [[ -z "$VPS_HOST" ]]; then
        warn "VPS_HOST not set — skipping deployment."
        warn "Set it in ${PROJECT_ROOT}/.env:  VPS_HOST=yourstockforecast.com"
        exit 0
    fi

    info "Step 3/3: Deploying to ${VPS_USER}@${VPS_HOST}:${VPS_PATH}…"
    rsync -avz --delete \
        --exclude '.DS_Store' \
        "${HUGO_SITE}/public/" \
        "${VPS_USER}@${VPS_HOST}:${VPS_PATH}/"

    if [[ "$VPS_NGINX_RELOAD" == "true" ]]; then
        info "Reloading Nginx on VPS…"
        ssh "${VPS_USER}@${VPS_HOST}" "sudo nginx -t && sudo systemctl reload nginx"
    fi
    success "Deployed to https://${VPS_HOST}"
fi

echo
success "Build pipeline complete!  $(date '+%H:%M:%S')"
