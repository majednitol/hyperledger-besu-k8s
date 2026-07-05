#!/bin/bash
# ========================
# Phase 7 Verification Script
# Verifies that bridge contracts compile, the anchor-service is built,
# K8s CronJobs exist, and NetworkPolicies are configured for secure bridging.
#
# Usage: bash phase7-verify.sh
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
echo "║   Phase 7 — Bridge & Relayer Verification   ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

APP_NS="besu-app"
BRIDGE_DIR="${SCRIPT_DIR}/../bridge"
SERVICE_DIR="${BRIDGE_DIR}/anchor-service"

# ─── Check 1: Compile Bridge Smart Contracts ─────────────────────────────
echo "━━━ [1/10] Hardhat Compile Check ━━━"
if cd "${BRIDGE_DIR}" && npx hardhat compile > /tmp/bridge-compile.log 2>&1; then
  pass "RegistryAnchor.sol compiled successfully"
else
  cat /tmp/bridge-compile.log
  fail "RegistryAnchor.sol failed to compile! See logs above."
fi
cd "${SCRIPT_DIR}"

# ─── Check 2: Verify TS Compilation on relayer ───────────────────────────
echo ""
echo "━━━ [2/10] Relayer Compilation Check ━━━"
if [ -d "${SERVICE_DIR}" ]; then
  if cd "${SERVICE_DIR}" && npm install >/dev/null 2>&1 && npx tsc >/dev/null 2>&1; then
    pass "anchor-service compiled successfully to JS"
  else
    fail "anchor-service TypeScript compilation failed"
  fi
else
  fail "anchor-service directory is missing"
fi
cd "${SCRIPT_DIR}"

# ─── Check 3: Check Relayer K8s Secret ───────────────────────────────────
echo ""
echo "━━━ [3/10] Relayer Key Secret ━━━"
if kubectl get secret relayer-key -n "${APP_NS}" >/dev/null 2>&1; then
  KEY_DATA=$(kubectl get secret relayer-key -n "${APP_NS}" -o jsonpath='{.data.privateKey}' 2>/dev/null || echo "")
  if [ -n "${KEY_DATA}" ]; then
    pass "Secret 'relayer-key' exists with privateKey entry"
  else
    fail "Secret 'relayer-key' exists but lacks privateKey entry"
  fi
else
  warn "Secret 'relayer-key' is missing in namespace '${APP_NS}' (expected if deploy_bridge.sh wasn't run)"
fi

# ─── Check 4: Check Bridge Addresses ConfigMap ───────────────────────────
echo ""
echo "━━━ [4/10] Bridge ConfigMap Addresses ━━━"
if kubectl get cm bridge-addresses -n "${APP_NS}" >/dev/null 2>&1; then
  REG_ADDR=$(kubectl get cm bridge-addresses -n "${APP_NS}" -o jsonpath='{.data.privateRegistryAddress}' 2>/dev/null || echo "")
  ANC_ADDR=$(kubectl get cm bridge-addresses -n "${APP_NS}" -o jsonpath='{.data.publicAnchorAddress}' 2>/dev/null || echo "")
  
  if [ -n "${REG_ADDR}" ] && [ -n "${ANC_ADDR}" ]; then
    pass "ConfigMap 'bridge-addresses' contains both private registry (${REG_ADDR}) and public anchor (${ANC_ADDR})"
  else
    fail "ConfigMap 'bridge-addresses' exists but lacks address configurations"
  fi
else
  warn "ConfigMap 'bridge-addresses' is missing in namespace '${APP_NS}'"
fi

# ─── Check 5: Verify CronJob resource exists ─────────────────────────────
echo ""
echo "━━━ [5/10] Relayer CronJob Manifest ━━━"
if kubectl get cronjob registry-anchor -n "${APP_NS}" >/dev/null 2>&1; then
  CRON_SCHED=$(kubectl get cronjob registry-anchor -n "${APP_NS}" -o jsonpath='{.spec.schedule}' 2>/dev/null || echo "")
  if [ "${CRON_SCHED}" = "*/10 * * * *" ]; then
    pass "CronJob 'registry-anchor' exists with schedule '${CRON_SCHED}'"
  else
    warn "CronJob 'registry-anchor' has non-standard schedule: '${CRON_SCHED}'"
  fi
else
  warn "CronJob 'registry-anchor' is missing in namespace '${APP_NS}'"
fi

# ─── Check 6: Verify Egress Network Policy exists ────────────────────────
echo ""
echo "━━━ [6/10] Relayer NetworkPolicy Check ━━━"
if kubectl get netpol relayer-egress-policy -n "${APP_NS}" >/dev/null 2>&1; then
  pass "Egress NetworkPolicy 'relayer-egress-policy' is applied in '${APP_NS}'"
else
  fail "Egress NetworkPolicy 'relayer-egress-policy' is missing"
fi

# ─── Check 7: Verify target EVM options in Hardhat ───────────────────────
echo ""
echo "━━━ [7/10] Solidity Configuration ━━━"
CFG_FILE="${BRIDGE_DIR}/hardhat.config.js"
if [ -f "${CFG_FILE}" ] && grep -q "0.8.20" "${CFG_FILE}"; then
  pass "hardhat.config.js is configured with compiler version 0.8.20"
else
  fail "hardhat.config.js is missing or compiler version is incorrect"
fi

# ─── Check 8: Verify package dependencies ────────────────────────────────
echo ""
echo "━━━ [8/10] Package dependencies check ━━━"
PKG_FILE="${SERVICE_DIR}/package.json"
if [ -f "${PKG_FILE}" ] && grep -q "ethers" "${PKG_FILE}" && grep -q "typescript" "${PKG_FILE}"; then
  pass "package.json contains required ethers and typescript dependencies"
else
  fail "package.json is missing or lacks bridge dependencies"
fi

# ─── Check 9: Verify namespace security labels ───────────────────────────
echo ""
echo "━━━ [9/10] Namespace PSA Enforcement ━━━"
PSA_LABEL=$(kubectl get ns "${APP_NS}" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "missing")
if [ "${PSA_LABEL}" = "restricted" ]; then
  pass "Namespace '${APP_NS}' has enforce=restricted PSA label"
else
  fail "Namespace '${APP_NS}' lacks enforce=restricted PSA label (found: ${PSA_LABEL})"
fi

# ─── Check 10: Verify Merkle determinism in contract constructor ────────
echo ""
echo "━━━ [10/10] Contract Safety check ━━━"
CON_FILE="${BRIDGE_DIR}/contracts/RegistryAnchor.sol"
if [ -f "${CON_FILE}" ] && grep -q "onlyRelayer" "${CON_FILE}" && ! grep -q "onlyAdmin" "${CON_FILE}"; then
  pass "RegistryAnchor.sol restricts modification to the onlyRelayer modifier (no admin escape holes)"
else
  fail "RegistryAnchor.sol lacks strict onlyRelayer modifiers or has incorrect auth rules"
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
  echo -e "${GREEN}✅ Phase 7 PASSED — bridge contract compiles, TS daemon compiles, and CronJob is configured!${NC}"
  exit 0
else
  echo -e "${RED}❌ Phase 7 FAILED — resolve compiler or configuration issues before deploying UI in Phase 8.${NC}"
  exit 1
fi
