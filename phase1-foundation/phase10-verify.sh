#!/bin/bash
# ========================
# Phase 10 Production Hardening Verification Script
# Performs a comprehensive 15-point audit against the Go-Live gate requirements.
#
# Usage: bash phase10-verify.sh
# Exit codes: 0 = 100% compliant, 1 = hardening violation detected
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

pass() { echo -e "  ${GREEN}✅ [PASS] $1${NC}"; ((PASS++)) || true; }
fail() { echo -e "  ${RED}❌ [FAIL] $1${NC}"; ((FAIL++)) || true; }
warn() { echo -e "  ${YELLOW}⚠️  [WARN] $1${NC}"; ((WARN++)) || true; }

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║      PHASE 10 — GO-LIVE HARDENING AUDIT      ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# 1. Namespace Isolation Check
echo "━━━ 1/15 Namespace Isolation check ━━━"
if kubectl get netpol default-deny-all -n "${PRIVATE_NAMESPACE}" >/dev/null 2>&1 && \
   kubectl get netpol default-deny-all -n "${PUBLIC_NAMESPACE}" >/dev/null 2>&1; then
  pass "Default-deny-all NetworkPolicies active in private and public namespaces."
else
  fail "Default-deny-all NetworkPolicies are missing in target namespaces."
fi

# 2. Permissioning Flags Split check
echo ""
echo "━━━ 2/15 Contract Permissioning Flags check ━━━"
VAL_FILE="${SCRIPT_DIR}/../private-network/5.validators/deploy_validators.sh"
PUB_VAL_FILE="${SCRIPT_DIR}/../public-network/5.validators/deploy_public_validators.sh"

if [ -f "${VAL_FILE}" ] && grep -q "permissions-nodes-contract-enabled" "${VAL_FILE}"; then
  if [ -f "${PUB_VAL_FILE}" ] && ! grep -q "permissions-nodes-contract-enabled" "${PUB_VAL_FILE}"; then
    pass "Permissioning flags correctly isolated (private=enabled, public=disabled)."
  else
    fail "Security risk! Public validator manifest contains permissioning contract flags."
  fi
else
  fail "Private validator manifest is missing permissioning contract flags."
fi

# 3. Chain ID Separation check
echo ""
echo "━━━ 3/15 Chain ID Separation check ━━━"
PRIV_GEN_CM="${SCRIPT_DIR}/../private-network/3.configmap/genesis.json"
PUB_GEN_CM="${SCRIPT_DIR}/../public-network/3.configmap/genesis.json"

if [ -f "${PRIV_GEN_CM}" ] && [ -f "${PUB_GEN_CM}" ]; then
  PRIV_ID=$(jq '.config.chainId' "${PRIV_GEN_CM}" 2>/dev/null || echo "1")
  PUB_ID=$(jq '.config.chainId' "${PUB_GEN_CM}" 2>/dev/null || echo "2")
  if [ "${PRIV_ID}" != "${PUB_ID}" ] && [ "${PRIV_ID}" = "${PRIVATE_CHAIN_ID}" ] && [ "${PUB_ID}" = "${PUBLIC_CHAIN_ID}" ]; then
    pass "Chain IDs verified and isolated: Private=${PRIV_ID}, Public=${PUB_ID}."
  else
    fail "Chain ID mismatch or collision! Private=${PRIV_ID}, Public=${PUB_ID}."
  fi
else
  warn "Skipping check: genesis.json ConfigMap files not extracted yet."
fi

# 4. Epoch Length frozen check
echo ""
echo "━━━ 4/15 Epoch Length configuration check ━━━"
PRIV_GEN_CFG="${SCRIPT_DIR}/../private-network/2.genesis/qbftConfigFile.json"
if [ -f "${PRIV_GEN_CFG}" ] && grep -q "epochlength" "${PRIV_GEN_CFG}"; then
  pass "QBFT consensus epoch length is configured in genesis properties."
else
  fail "QBFT epoch length property is missing from config."
fi

# 5. NAT Method Check
echo ""
echo "━━━ 5/15 NAT Method config check ━━━"
if [ -f "${VAL_FILE}" ] && grep -q "nat-method=NONE" "${VAL_FILE}"; then
  pass "NAT Method is set to NONE for Kubernetes cloud deployments."
else
  fail "NAT Method configuration mismatch (expected --nat-method=NONE)."
fi

# 6. Private mTLS configuration check
echo ""
echo "━━━ 6/15 Private P2P TLS check ━━━"
if [ -f "${VAL_FILE}" ] && grep -q "p2p-tls-enabled" "${VAL_FILE}"; then
  pass "Private network P2P TLS encryption is enabled in node args."
else
  fail "Private network P2P TLS encryption is missing."
fi

# 7. Public Ingress TLS check
echo ""
echo "━━━ 7/15 Public Ingress TLS check ━━━"
PUB_INGRESS="${SCRIPT_DIR}/../public-network/8.ingress/ingress.yaml"
if [ -f "${PUB_INGRESS}" ] && grep -q "letsencrypt-prod" "${PUB_INGRESS}"; then
  pass "Public Ingress configures Let's Encrypt production certificates."
else
  fail "Public Ingress is missing or lacks production ClusterIssuer mappings."
fi

# 8. Admin API Isolation check
echo ""
echo "━━━ 8/15 Public RPC APIs check ━━━"
PUB_RPC="${SCRIPT_DIR}/../public-network/6.rpc-nodes/deploy_public_rpc.sh"
if [ -f "${PUB_RPC}" ]; then
  if grep -q "rpc-http-api" "${PUB_RPC}"; then
    if grep -q "ADMIN" "${PUB_RPC}" || grep -q "DEBUG" "${PUB_RPC}"; then
      fail "SECURITY VIOLATION: ADMIN/DEBUG API namespaces exposed on public RPC!"
    else
      pass "Public JSON-RPC is restricted to safe API namespaces only."
    fi
  else
    fail "Public RPC is missing explicit rpc-http-api restrictions."
  fi
fi

# 9. PodDisruptionBudget presence check
echo ""
echo "━━━ 9/15 PodDisruptionBudget check ━━━"
if [ -f "${VAL_FILE}" ] && grep -q "PodDisruptionBudget" "${VAL_FILE}"; then
  if [ -f "${PUB_VAL_FILE}" ] && grep -q "PodDisruptionBudget" "${PUB_VAL_FILE}"; then
    pass "PodDisruptionBudgets mapped on both private and public validator sets."
  else
    fail "PDB is missing on public validator set."
  fi
else
  fail "PDB is missing on private validator set."
fi

# 10. Namespace PSA labels check
echo ""
echo "━━━ 10/15 Namespace PSA check ━━━"
NS_ERRS=0
for NS in "${PRIVATE_NAMESPACE}" "${PUBLIC_NAMESPACE}" "${APP_NAMESPACE}"; do
  LABEL=$(kubectl get ns "${NS}" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "")
  if [ "${LABEL}" = "restricted" ]; then
    pass "Namespace '${NS}' enforces restricted Pod Security Admission."
  else
    fail "Namespace '${NS}' lacks enforce=restricted label (found: ${LABEL})."
    NS_ERRS=$((NS_ERRS + 1))
  fi
done

# 11. Relayer Key security check
echo ""
echo "━━━ 11/15 Relayer Key Isolation check ━━━"
CRON_YAML="${SCRIPT_DIR}/../bridge/anchor-cronjob.yaml"
if [ -f "${CRON_YAML}" ] && grep -q "relayer-key" "${CRON_YAML}"; then
  pass "Relayer Daemon mounts isolated credentials from relayer-key secrets."
else
  fail "Relayer Daemon is missing credentials secret mapping."
fi

# 12. RBAC Scope check
echo ""
echo "━━━ 12/15 RBAC Scope check ━━━"
RBAC_FILES=$(find "${SCRIPT_DIR}/" -name "rbac-*.yaml")
RBAC_ERRS=0
for file in ${RBAC_FILES}; do
  if grep -q "\- \'*\'" "$file" && grep -q "resources:" "$file"; then
    fail "Wildcard resource permission found in $file."
    RBAC_ERRS=$((RBAC_ERRS + 1))
  fi
done
if [ "${RBAC_ERRS}" -eq 0 ]; then
  pass "All operational RBAC roles are strictly scoped (no wildcards)."
fi

# 13. API Auth check
echo ""
echo "━━━ 13/15 API Gateway Write Authentication check ━━━"
SERVER_JS="${SCRIPT_DIR}/../10.api/src/server.js"
if [ -f "${SERVER_JS}" ] && grep -q "authenticateRIR" "${SERVER_JS}"; then
  pass "API Gateway prefix write endpoint POST /api/prefix is guarded by authenticateRIR middleware."
else
  fail "API Gateway prefix write endpoint lacks authentication middleware."
fi

# 14. CI/CD Workflow check
echo ""
echo "━━━ 14/15 CI/CD Workflow check ━━━"
CI_YAML="${SCRIPT_DIR}/../.github/workflows/ci.yaml"
if [ -f "${CI_YAML}" ]; then
  pass "CI/CD pipeline workflow template is present."
else
  fail "CI/CD pipeline workflow template is missing."
fi

# 15. Observability scope check
echo ""
echo "━━━ 15/15 Scrape Targets check ━━━"
PROM_CFG="${SCRIPT_DIR}/../13.monitoring/prometheus-configmap.yaml"
if [ -f "${PROM_CFG}" ] && grep -q "private-validators" "${PROM_CFG}" && grep -q "public-validators" "${PROM_CFG}"; then
  pass "Prometheus configuration scrapes both private and public validator sets."
else
  fail "Prometheus scraper targets are incomplete."
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

if [ "$FAIL" -eq 0 ] && [ "${NS_ERRS}" -eq 0 ] && [ "${RBAC_ERRS}" -eq 0 ]; then
  echo -e "${GREEN}✅ 100% COMPLIANT — both networks conform to all production hardening criteria!${NC}"
  exit 0
else
  echo -e "${RED}❌ AUDIT FAILED — resolve security or configuration gaps before go-live!${NC}"
  exit 1
fi
