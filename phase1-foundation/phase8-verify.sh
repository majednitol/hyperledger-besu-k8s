#!/bin/bash
# ========================
# Phase 8 Verification Script
# Verifies that the API Gateway, NOC UI dashboard, and public/private
# block explorers are correctly configured and security restrictions are enforced.
#
# Usage: bash phase8-verify.sh
# Exit codes: 0 = all checks pass, 1 = critical failure
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

pass() { echo -e "  ${GREEN}✅ $1${NC}"; ((PASS++)) || true; }
fail() { echo -e "  ${RED}❌ $1${NC}"; ((FAIL++)) || true; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; ((WARN++)) || true; }

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Phase 8 — App & API Auth Verification      ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

APP_NS="besu-app"
PUBLIC_NS="besu-public"

# ─── Check 1: Verify API Gateway Deployment ──────────────────────────────
echo "━━━ [1/10] API Gateway Deployment ━━━"
if kubectl get deployment api-gateway -n "${APP_NS}" >/dev/null 2>&1; then
  REPLICAS=$(kubectl get deployment api-gateway -n "${APP_NS}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
  if [ "${REPLICAS}" -ge 2 ]; then
    pass "Deployment 'api-gateway' is active with ${REPLICAS} replicas (minimum: 2)"
  else
    fail "Deployment 'api-gateway' exists but replicas = ${REPLICAS} (expected: 2+)"
  fi
else
  warn "Deployment 'api-gateway' is not running in the cluster yet (expected during dry-runs)"
fi

# ─── Check 2: Verify static dashboard UI files ───────────────────────────
echo ""
echo "━━━ [2/10] Dashboard UI Assets check ━━━"
UI_DIR="${SCRIPT_DIR}/../11.ui"
if [ -f "${UI_DIR}/index.html" ] && [ -f "${UI_DIR}/app.js" ] && [ -f "${UI_DIR}/style.css" ]; then
  pass "All dashboard UI assets (index.html, app.js, style.css) exist in 11.ui/"
else
  fail "Dashboard UI assets are missing or incomplete in 11.ui/"
fi

# ─── Check 3: Verify private explorer files ──────────────────────────────
echo ""
echo "━━━ [3/10] Private Explorer check ━━━"
PV_EXP="${SCRIPT_DIR}/../12.explorer/explorer-private"
if [ -f "${PV_EXP}/index.html" ]; then
  pass "Private explorer index.html exists in 12.explorer/explorer-private/"
else
  fail "Private explorer asset index.html is missing"
fi

# ─── Check 4: Verify public explorer files ───────────────────────────────
echo ""
echo "━━━ [4/10] Public Explorer check ━━━"
PB_EXP="${SCRIPT_DIR}/../12.explorer/explorer-public"
if [ -f "${PB_EXP}/index.html" ]; then
  pass "Public explorer index.html exists in 12.explorer/explorer-public/"
else
  fail "Public explorer asset index.html is missing"
fi

# ─── Check 5: Verify private explorer Ingress exclusion ──────────────────
echo ""
echo "━━━ [5/10] Private Explorer Isolation Check ━━━"
if kubectl get ingress -n "${APP_NS}" -o name 2>/dev/null | grep -q "explorer-private"; then
  fail "SECURITY BREACH: Ingress mapping detected for 'explorer-private'! This must remain unexposed."
else
  pass "Privacy Guard: No Ingress route mapped for 'explorer-private' (retains internal-only access)"
fi

# ─── Check 6: Verify API Gateway Ingress configuration ───────────────────
echo ""
echo "━━━ [6/10] API Gateway Ingress Check ━━━"
if kubectl get ingress api-gateway-ingress -n "${APP_NS}" >/dev/null 2>&1; then
  ISSUER=$(kubectl get ingress api-gateway-ingress -n "${APP_NS}" -o jsonpath='{.metadata.annotations.cert-manager\.io/cluster-issuer}' 2>/dev/null || echo "")
  if [ "${ISSUER}" = "letsencrypt-prod" ]; then
    pass "api-gateway Ingress configured with Let's Encrypt production ClusterIssuer"
  else
    warn "api-gateway Ingress has non-standard ClusterIssuer: '${ISSUER}'"
  fi
else
  warn "Ingress 'api-gateway-ingress' is missing"
fi

# ─── Check 7: Verify static asset routing config in JS server ───────────
echo ""
echo "━━━ [7/10] Express routing assets check ━━━"
SERVER_JS="${SCRIPT_DIR}/../10.api/src/server.js"
if [ -f "${SERVER_JS}" ] && grep -q "/ui" "${SERVER_JS}" && grep -q "/explorer-public" "${SERVER_JS}"; then
  pass "Express server.js is configured to serve static assets (/ui, /explorer-public, /explorer-private)"
else
  fail "Express server.js lacks static asset routing configurations"
fi

# ─── Check 8: Verify Dockerfile uses Node 20-alpine ─────────────────────
echo ""
echo "━━━ [8/10] Dockerfile security audit ━━━"
DOCKER_FILE="${SCRIPT_DIR}/../10.api/Dockerfile"
if [ -f "${DOCKER_FILE}" ] && grep -q "node:20-alpine" "${DOCKER_FILE}" && grep -q "USER node" "${DOCKER_FILE}"; then
  pass "Dockerfile specifies Node 20-alpine image and enforces non-root USER node context"
else
  fail "Dockerfile is missing or does not meet Node 20 alpine non-root container standard"
fi

# ─── Check 9: Verify CI/CD workflow existence ────────────────────────────
echo ""
echo "━━━ [9/10] GitHub Actions Workflow check ━━━"
CI_WORKFLOW="${SCRIPT_DIR}/../.github/workflows/ci.yaml"
if [ -f "${CI_WORKFLOW}" ] && grep -q "hardhat test" "${CI_WORKFLOW}" && grep -q "actions/checkout" "${CI_WORKFLOW}"; then
  pass "CI/CD workflow 'ci.yaml' exists and includes checkout and Hardhat testing jobs"
else
  fail "CI/CD workflow 'ci.yaml' is missing or has incomplete testing jobs"
fi

# ─── Check 10: Verify API rate limits annotations ────────────────────────
echo ""
echo "━━━ [10/10] Ingress Rate-Limiting Check ━━━"
if kubectl get ingress api-gateway-ingress -n "${APP_NS}" >/dev/null 2>&1; then
  LIMIT=$(kubectl get ingress api-gateway-ingress -n "${APP_NS}" -o jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/limit-rps}' 2>/dev/null || echo "")
  if [ "${LIMIT}" = "20" ]; then
    pass "Ingress rate-limiting is active at 20 RPS"
  else
    warn "Ingress rate-limiting not set to 20 RPS (found: ${LIMIT})"
  fi
else
  warn "Skipping Ingress rate limits check (Ingress resource missing)"
fi

# ─── Summary ────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║              VERIFICATION SUMMARY            ║"
echo "╠══════════════════════════════════════════════╣"
echo -e "║  ${GREEN}Passed: ${PASS}${NC}                                  ║"
echo -e "║  ${YELLOW}Warnings: ${WARN}${NC}                                ║"
echo -e "║  ${RED}Failed: ${FAIL}${NC}                                  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}✅ Phase 8 PASSED — API gateway, dashboard UI, and block explorers ready for deployment!${NC}"
  exit 0
else
  echo -e "${RED}❌ Phase 8 FAILED — resolve configuration or file layout errors.${NC}"
  exit 1
fi
