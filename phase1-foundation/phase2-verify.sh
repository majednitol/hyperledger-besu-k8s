#!/bin/bash
# ========================
# Phase 2 Verification Script
# Checks that all genesis config, keys, and TLS certificate manifests exist
# and are correctly applied to the Kubernetes cluster.
#
# Usage: bash phase2-verify.sh
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
echo "║   Phase 2 — Preparation Verification Script  ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

NAMESPACE="${PRIVATE_NAMESPACE}"

# ─── Check 1: Genesis ConfigMap exists ──────────────────────────────────
echo "━━━ [1/10] Genesis ConfigMap ━━━"
if kubectl get cm besu-private-genesis -n "${NAMESPACE}" >/dev/null 2>&1; then
  # Extract chainId to verify
  CHAIN_ID=$(kubectl get cm besu-private-genesis -n "${NAMESPACE}" -o jsonpath='{.data.genesis\.json}' | jq -r '.config.chainId' 2>/dev/null || echo "unknown")
  if [ "${CHAIN_ID}" = "${PRIVATE_CHAIN_ID}" ]; then
    pass "Genesis ConfigMap exists and chainId matches PRIVATE_CHAIN_ID (${CHAIN_ID})"
  else
    fail "Genesis ConfigMap exists but chainId (${CHAIN_ID}) does not match PRIVATE_CHAIN_ID (${PRIVATE_CHAIN_ID})"
  fi
else
  fail "Genesis ConfigMap 'besu-private-genesis' does not exist"
fi

# ─── Check 2: Validator Secrets exist ───────────────────────────────────
echo ""
echo "━━━ [2/10] Node Key Secrets ━━━"
VAL_NAMES=("afrinic" "apnic" "arin" "ripencc" "lacnic" "rono" "rono-2")
RPC_NAMES=("afrinic" "apnic" "arin" "ripencc" "lacnic" "rono")
ALL_SECRETS=()

for ORG in "${VAL_NAMES[@]}"; do ALL_SECRETS+=("validator-${ORG}-key"); done
for i in 1 2; do ALL_SECRETS+=("bootnode-${i}-key"); done
for ORG in "${RPC_NAMES[@]}"; do ALL_SECRETS+=("rpc-${ORG}-key"); done

MISSING_SECRETS=0
for SECRET in "${ALL_SECRETS[@]}"; do
  if kubectl get secret "${SECRET}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    # Check data keys
    KEY_EXISTS=$(kubectl get secret "${SECRET}" -n "${NAMESPACE}" -o jsonpath='{.data.key}' 2>/dev/null || echo "")
    PUB_EXISTS=$(kubectl get secret "${SECRET}" -n "${NAMESPACE}" -o jsonpath='{.data.key\.pub}' 2>/dev/null || echo "")
    if [ -n "${KEY_EXISTS}" ] && [ -n "${PUB_EXISTS}" ]; then
      pass "Secret '${SECRET}' exists with key and key.pub"
    else
      fail "Secret '${SECRET}' exists but lacks key/key.pub keys"
      ((MISSING_SECRETS++)) || true
    fi
  else
    fail "Secret '${SECRET}' is missing"
    ((MISSING_SECRETS++)) || true
  fi
done

# ─── Check 3: Static-nodes ConfigMap exists ─────────────────────────────
echo ""
echo "━━━ [3/10] Static Nodes Configuration ━━━"
if kubectl get cm besu-private-static-nodes -n "${NAMESPACE}" >/dev/null 2>&1; then
  # Count entries
  NODE_COUNT=$(kubectl get cm besu-private-static-nodes -n "${NAMESPACE}" -o jsonpath='{.data.static-nodes\.json}' | jq '. | length' 2>/dev/null || echo "0")
  EXPECTED_NODES=$(( PRIVATE_BOOTNODE_COUNT + PRIVATE_VALIDATOR_COUNT ))
  if [ "${NODE_COUNT}" -eq "${EXPECTED_NODES}" ]; then
    pass "Static nodes ConfigMap contains all ${EXPECTED_NODES} nodes (2 bootnodes + 7 validators)"
  else
    warn "Static nodes ConfigMap contains ${NODE_COUNT} nodes (expected: ${EXPECTED_NODES})"
  fi
else
  fail "ConfigMap 'besu-private-static-nodes' is missing"
fi

# ─── Check 4: Local Permissioning ConfigMap exists ─────────────────────
echo ""
echo "━━━ [4/10] Local Permissioning Configuration ━━━"
if kubectl get cm besu-private-permissions -n "${NAMESPACE}" >/dev/null 2>&1; then
  # Extract node and account lists
  PERMS_CONTENT=$(kubectl get cm besu-private-permissions -n "${NAMESPACE}" -o jsonpath='{.data.permissions_config\.toml}' 2>/dev/null || echo "")
  if echo "${PERMS_CONTENT}" | grep -q "nodes-allowlist" && echo "${PERMS_CONTENT}" | grep -q "accounts-allowlist"; then
    pass "Permissions ConfigMap exists with nodes-allowlist and accounts-allowlist"
  else
    fail "Permissions ConfigMap missing nodes-allowlist or accounts-allowlist"
  fi
else
  fail "ConfigMap 'besu-private-permissions' is missing"
fi

# ─── Check 5: cert-manager Issuer is Active ─────────────────────────────
echo ""
echo "━━━ [5/10] cert-manager Issuer status ━━━"
if kubectl get issuer besu-private-ca-issuer -n "${NAMESPACE}" >/dev/null 2>&1; then
  # Check readiness condition
  ISSUER_READY=$(kubectl get issuer besu-private-ca-issuer -n "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
  if [ "${ISSUER_READY}" = "True" ]; then
    pass "Issuer 'besu-private-ca-issuer' is Ready"
  else
    warn "Issuer 'besu-private-ca-issuer' exists but is NOT Ready (status: ${ISSUER_READY})"
  fi
else
  fail "cert-manager Issuer 'besu-private-ca-issuer' is missing"
fi

# ─── Check 6: TLS Certificate Secrets exist ─────────────────────────────
echo ""
echo "━━━ [6/10] TLS secrets ━━━"
TLS_SECRETS=()
for ORG in "${VAL_NAMES[@]}"; do TLS_SECRETS+=("validator-${ORG}-tls"); done
for i in 1 2; do TLS_SECRETS+=("bootnode-${i}-tls"); done
for ORG in "${RPC_NAMES[@]}"; do TLS_SECRETS+=("rpc-${ORG}-tls"); done

MISSING_TLS=0
for TLS in "${TLS_SECRETS[@]}"; do
  if kubectl get secret "${TLS}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    P12_EXISTS=$(kubectl get secret "${TLS}" -n "${NAMESPACE}" -o jsonpath='{.data.keystore\.pfx}' 2>/dev/null || echo "")
    CRT_EXISTS=$(kubectl get secret "${TLS}" -n "${NAMESPACE}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || echo "")
    if [ -n "${P12_EXISTS}" ] && [ -n "${CRT_EXISTS}" ]; then
      pass "TLS Secret '${TLS}' contains keystore.pfx and tls.crt"
    else
      fail "TLS Secret '${TLS}' lacks keystore.pfx or tls.crt"
      ((MISSING_TLS++)) || true
    fi
  else
    fail "TLS Secret '${TLS}' is missing"
    ((MISSING_TLS++)) || true
  fi
done

# ─── Check 7: known-clients.txt ConfigMap exists ────────────────────────
echo ""
echo "━━━ [7/10] mTLS known-clients.txt Configuration ━━━"
if kubectl get cm besu-private-known-clients -n "${NAMESPACE}" >/dev/null 2>&1; then
  # Check line count
  LCOUNT=$(kubectl get cm besu-private-known-clients -n "${NAMESPACE}" -o jsonpath='{.data.known-clients\.txt}' | wc -l | tr -d ' ')
  EXPECTED_COUNT=15 # 7 validators + 2 bootnodes + 6 RPC nodes
  if [ "${LCOUNT}" -eq "${EXPECTED_COUNT}" ]; then
    pass "known-clients.txt exists and contains all ${EXPECTED_COUNT} TLS fingerprints"
  else
    warn "known-clients.txt contains ${LCOUNT} fingerprints (expected: ${EXPECTED_COUNT})"
  fi
else
  fail "ConfigMap 'besu-private-known-clients' is missing"
fi

# ─── Check 8: No running Besu node pods ─────────────────────────────────
echo ""
echo "━━━ [8/10] Active Node Guard (Phase 2 = prep only) ━━━"
RUNNING_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app --field-selector=status.phase=Running -o name 2>/dev/null || echo "")
if [ -z "${RUNNING_PODS}" ]; then
  pass "No running Besu node pods found (correct for Phase 2 preparation)"
else
  fail "Running Besu node pods found: ${RUNNING_PODS}. Nodes should NOT run until Phase 3!"
fi

# ─── Check 9: Workspace ConfigMap Directory Synced ─────────────────────
echo ""
echo "━━━ [9/10] Workspace Configurations Check ━━━"
if [ -f "${SCRIPT_DIR}/../3.configmap/genesis.json" ] && [ -f "${SCRIPT_DIR}/../3.configmap/static-nodes.json" ] && [ -f "${SCRIPT_DIR}/../3.configmap/permissions_config.toml" ] && [ -f "${SCRIPT_DIR}/../3.configmap/known-clients.txt" ]; then
  pass "Workspace configmap/ folder successfully synced with extracted configuration files"
else
  warn "Workspace configmap/ files are missing or incomplete. Sync with extract-keys.sh."
fi

# ─── Check 10: Private namespace PSA enforcement confirmation ──────────
echo ""
echo "━━━ [10/10] Namespace Validation ━━━"
PSA_LABEL=$(kubectl get ns "${NAMESPACE}" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || echo "missing")
if [ "${PSA_LABEL}" = "restricted" ]; then
  pass "Namespace '${NAMESPACE}' has restricted PSA label"
else
  fail "Namespace '${NAMESPACE}' lacks enforce=restricted PSA label (found: ${PSA_LABEL})"
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
  echo -e "${GREEN}✅ Phase 2 PASSED — all cryptographic and configuration items are prepared!${NC}"
  exit 0
else
  echo -e "${RED}❌ Phase 2 FAILED — fix $FAIL issues before moving to Phase 3 node deployment.${NC}"
  exit 1
fi
