#!/bin/bash
# ========================
# Phase 5 Verification Script
# Checks that public network genesis configs, validator keys, and Ingress
# Let's Encrypt CA ClusterIssuers exist and are properly configured.
#
# Usage: bash phase5-verify.sh
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

pass() { echo -e "  ${GREEN}✅ $1${NC}"; ((PASS++)); }
fail() { echo -e "  ${RED}❌ $1${NC}"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; ((WARN++)); }

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Phase 5 — Public Network Prep Verification ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

NAMESPACE="${PUBLIC_NAMESPACE}"

# ─── Check 1: Genesis ConfigMap exists ──────────────────────────────────
echo "━━━ [1/10] Public Genesis ConfigMap ━━━"
if kubectl get cm besu-public-genesis -n "${NAMESPACE}" >/dev/null 2>&1; then
  pass "Public Genesis ConfigMap 'besu-public-genesis' exists"
else
  fail "Public Genesis ConfigMap 'besu-public-genesis' does not exist"
fi

# ─── Check 2: Verify Chain ID ────────────────────────────────────────────
echo ""
echo "━━━ [2/10] Public Chain ID Check ━━━"
if kubectl get cm besu-public-genesis -n "${NAMESPACE}" >/dev/null 2>&1; then
  CHAIN_ID=$(kubectl get cm besu-public-genesis -n "${NAMESPACE}" -o jsonpath='{.data.genesis\.json}' | jq -r '.config.chainId' 2>/dev/null || echo "unknown")
  if [ "${CHAIN_ID}" = "${PUBLIC_CHAIN_ID}" ]; then
    pass "Public genesis chainId matches PUBLIC_CHAIN_ID (${CHAIN_ID})"
  else
    fail "Public genesis chainId (${CHAIN_ID}) does not match PUBLIC_CHAIN_ID (${PUBLIC_CHAIN_ID})"
  fi
else
  fail "Skipping chain ID check (Genesis ConfigMap missing)"
fi

# ─── Check 3: Verify Empty Alloc object ──────────────────────────────────
echo ""
echo "━━━ [3/10] Permissionless Alloc Object Verification ━━━"
if kubectl get cm besu-public-genesis -n "${NAMESPACE}" >/dev/null 2>&1; then
  ALLOC_KEYS=$(kubectl get cm besu-public-genesis -n "${NAMESPACE}" -o jsonpath='{.data.genesis\.json}' | jq '.alloc | keys | length' 2>/dev/null || echo "unknown")
  if [ "${ALLOC_KEYS}" = "0" ]; then
    pass "Genesis 'alloc' object is empty (confirming no pre-allocated permissioning contracts)"
  else
    fail "Genesis 'alloc' object contains ${ALLOC_KEYS} pre-allocated items! This must be empty for the public network."
  fi
fi

# ─── Check 4: Confirm zero permissioning contract address cross-talk ────
echo ""
echo "━━━ [4/5] Ingress Permissioning Validation ━━━"
if kubectl get cm besu-public-genesis -n "${NAMESPACE}" >/dev/null 2>&1; then
  GENESIS_CONTENT=$(kubectl get cm besu-public-genesis -n "${NAMESPACE}" -o jsonpath='{.data.genesis\.json}' 2>/dev/null || echo "")
  if echo "${GENESIS_CONTENT}" | grep -q "0000000000000000000000000000000000009999" || echo "${GENESIS_CONTENT}" | grep -q "0000000000000000000000000000000000008888"; then
    fail "Accidental cross-talk detected! Ingress permissioning contract addresses (0x...9999 or 0x...8888) found in public genesis."
  else
    pass "No ingress permissioning contract addresses found in public genesis configuration"
  fi
fi

# ─── Check 5: Validator Key Secrets exist ────────────────────────────────
echo ""
echo "━━━ [5/10] Public Validator Key Secrets ━━━"
VAL_FAIL=0
for i in $(seq 1 5); do
  NAME="public-validator-${i}-key"
  if kubectl get secret "${NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    KEY_EXISTS=$(kubectl get secret "${NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.key}' 2>/dev/null || echo "")
    if [ -n "${KEY_EXISTS}" ]; then
      pass "Secret '${NAME}' exists with key data"
    else
      fail "Secret '${NAME}' exists but lacks key data"
      VAL_FAIL=$((VAL_FAIL + 1))
    fi
  else
    fail "Secret '${NAME}' is missing"
    VAL_FAIL=$((VAL_FAIL + 1))
  fi
done

# ─── Check 6: Bootnode Key Secrets exist ─────────────────────────────────
echo ""
echo "━━━ [6/10] Public Bootnode Key Secrets ━━━"
BOOT_FAIL=0
for i in $(seq 1 2); do
  NAME="public-bootnode-${i}-key"
  if kubectl get secret "${NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    KEY_EXISTS=$(kubectl get secret "${NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.key}' 2>/dev/null || echo "")
    if [ -n "${KEY_EXISTS}" ]; then
      pass "Secret '${NAME}' exists with key data"
    else
      fail "Secret '${NAME}' exists but lacks key data"
      BOOT_FAIL=$((BOOT_FAIL + 1))
    fi
  else
    fail "Secret '${NAME}' is missing"
    BOOT_FAIL=$((BOOT_FAIL + 1))
  fi
done

# ─── Check 7: Static Nodes ConfigMap exists ──────────────────────────────
echo ""
echo "━━━ [7/10] Static Nodes Configuration ━━━"
if kubectl get cm besu-public-static-nodes -n "${NAMESPACE}" >/dev/null 2>&1; then
  NODE_COUNT=$(kubectl get cm besu-public-static-nodes -n "${NAMESPACE}" -o jsonpath='{.data.static-nodes\.json}' | jq '. | length' 2>/dev/null || echo "0")
  EXPECTED_NODES=$(( PUBLIC_BOOTNODE_COUNT + PUBLIC_VALIDATOR_COUNT ))
  if [ "${NODE_COUNT}" -eq "${EXPECTED_NODES}" ]; then
    pass "Static nodes ConfigMap contains all ${EXPECTED_NODES} public nodes (2 bootnodes + 5 validators)"
  else
    warn "Static nodes ConfigMap contains ${NODE_COUNT} nodes (expected: ${EXPECTED_NODES})"
  fi
else
  fail "ConfigMap 'besu-public-static-nodes' is missing"
fi

# ─── Check 8: cert-manager ClusterIssuers ────────────────────────────────
echo ""
echo "━━━ [8/10] Ingress CA Issuers ━━━"
STAGING_STATUS=$(kubectl get clusterissuer letsencrypt-staging -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "missing")
PROD_STATUS=$(kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "missing")

if [ "${STAGING_STATUS}" = "True" ]; then
  pass "ClusterIssuer 'letsencrypt-staging' is Ready"
else
  warn "ClusterIssuer 'letsencrypt-staging' is NOT Ready (status: ${STAGING_STATUS})"
fi

if [ "${PROD_STATUS}" = "True" ]; then
  pass "ClusterIssuer 'letsencrypt-prod' is Ready"
else
  warn "ClusterIssuer 'letsencrypt-prod' is NOT Ready (status: ${PROD_STATUS})"
fi

# ─── Check 9: Public namespace PSA enforcement ──────────────────────────
echo ""
echo "━━━ [9/10] Namespace Validation ━━━"
PSA_LABEL=$(kubectl get ns "${NAMESPACE}" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "missing")
if [ "${PSA_LABEL}" = "restricted" ]; then
  pass "Namespace '${NAMESPACE}' has restricted PSA label"
else
  fail "Namespace '${NAMESPACE}' lacks enforce=restricted PSA label (found: ${PSA_LABEL})"
fi

# ─── Check 10: No running Besu node pods ─────────────────────────────────
echo ""
echo "━━━ [10/10] Active Node Guard (Phase 5 = prep only) ━━━"
RUNNING_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app --field-selector=status.phase=Running -o name 2>/dev/null || echo "")
if [ -z "${RUNNING_PODS}" ]; then
  pass "No running public Besu node pods found (correct for Phase 5 preparation)"
else
  fail "Running public Besu node pods found: ${RUNNING_PODS}. Nodes should NOT run until Phase 6!"
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

if [ "$FAIL" -eq 0 ] && [ "${VAL_FAIL}" -eq 0 ] && [ "${BOOT_FAIL}" -eq 0 ]; then
  echo -e "${GREEN}✅ Phase 5 PASSED — all cryptographic and public Ingress components are prepared!${NC}"
  exit 0
else
  echo -e "${RED}❌ Phase 5 FAILED — resolve active issues before deploying Phase 6 public nodes.${NC}"
  exit 1
fi
