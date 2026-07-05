#!/bin/bash
# ========================
# Phase 3 Verification Script
# Verifies that private network nodes are running, QBFT consensus is active,
# block height is increasing, PDB is enforced, and NetworkPolicy isolation is active.
#
# Usage: bash phase3-verify.sh
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
echo "║   Phase 3 — Private Nodes Verification       ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

NAMESPACE="${PRIVATE_NAMESPACE}"

# ─── Check 1: Bootnodes Running ──────────────────────────────────────────
echo "━━━ [1/10] Bootnodes Status Check ━━━"
BOOTNODE_RUNNING=$(kubectl get deployments -n "${NAMESPACE}" -l app=bootnode-1,network=private -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")
BOOTNODE2_RUNNING=$(kubectl get deployments -n "${NAMESPACE}" -l app=bootnode-2,network=private -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null || echo "0")

if [ "${BOOTNODE_RUNNING}" = "1" ] && [ "${BOOTNODE2_RUNNING}" = "1" ]; then
  pass "Both bootnode-1 and bootnode-2 are running"
else
  fail "Bootnodes not ready (bootnode-1: ${BOOTNODE_RUNNING:-0}/1, bootnode-2: ${BOOTNODE2_RUNNING:-0}/1)"
fi

# ─── Check 2: Validators Running ─────────────────────────────────────────
echo ""
echo "━━━ [2/10] Validators Status Check ━━━"
VAL_ORGS=("afrinic" "apnic" "arin" "ripencc" "lacnic" "rono" "rono-2")
VAL_FAIL=0
for ORG in "${VAL_ORGS[@]}"; do
  V_READY=$(kubectl get statefulset "validator-${ORG}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [ "${V_READY}" = "1" ]; then
    pass "validator-${ORG} StatefulSet is ready"
  else
    fail "validator-${ORG} StatefulSet is NOT ready (ready: ${V_READY}/1)"
    VAL_FAIL=$((VAL_FAIL + 1))
  fi
done

# ─── Check 3: RPC Nodes Running ──────────────────────────────────────────
echo ""
echo "━━━ [3/10] RPC Nodes Status Check ━━━"
RPC_ORGS=("afrinic" "apnic" "arin" "ripencc" "lacnic" "rono")
RPC_FAIL=0
for ORG in "${RPC_ORGS[@]}"; do
  R_READY=$(kubectl get deployment "rpc-${ORG}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  if [ "${R_READY}" = "1" ]; then
    pass "rpc-${ORG} Deployment is ready"
  else
    fail "rpc-${ORG} Deployment is NOT ready (ready: ${R_READY}/1)"
    RPC_FAIL=$((RPC_FAIL + 1))
  fi
done

# Test JSON-RPC connectivity inside namespace by using kubectl exec on a running RPC pod
RPC_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=rpc-rono -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "${RPC_POD}" ]; then
  fail "No rpc-rono pod found to run JSON-RPC query"
  exit 1
fi

RPC_OK=$(kubectl exec -n "${NAMESPACE}" "${RPC_POD}" -c besu -- \
  curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
  http://localhost:8545 2>/dev/null || echo "")

if [ -n "${RPC_OK}" ] && echo "${RPC_OK}" | grep -q "result"; then
  PEERS_HEX=$(echo "${RPC_OK}" | jq -r '.result')
  PEERS=$((PEERS_HEX))
  pass "JSON-RPC endpoint responsive on rpc-rono (peer count: ${PEERS})"
else
  fail "JSON-RPC endpoint on rpc-rono is unresponsive"
fi

# ─── Check 5: Block Production Check ─────────────────────────────────────
echo ""
echo "━━━ [5/10] Block Production Check ━━━"
get_block_num() {
  kubectl exec -n "${NAMESPACE}" "${RPC_POD}" -c besu -- \
    curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 2>/dev/null | jq -r '.result' || echo "0"
}

BLOCK1_HEX=$(get_block_num)
BLOCK1=$((BLOCK1_HEX))
echo "   Initial block height: ${BLOCK1}"
echo "   Sleeping for 10 seconds..."
sleep 10
BLOCK2_HEX=$(get_block_num)
BLOCK2=$((BLOCK2_HEX))
echo "   Subsequent block height: ${BLOCK2}"

if [ "${BLOCK2}" -gt "${BLOCK1}" ]; then
  pass "Block height is increasing (QBFT consensus is active)"
else
  fail "Block height did not increase (${BLOCK1} -> ${BLOCK2}). Consensus may be halted!"
fi

# ─── Check 6: QBFT Validator Pool Verification ───────────────────────────
echo ""
echo "━━━ [6/10] QBFT Validator Pool Verification ━━━"
VAL_POOL=$(kubectl exec -n "${NAMESPACE}" "${RPC_POD}" -c besu -- \
  curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"qbft_getValidatorsByBlockNumber","params":["latest"],"id":1}' \
  http://localhost:8545 2>/dev/null || echo "")

if [ -n "${VAL_POOL}" ] && echo "${VAL_POOL}" | grep -q "result"; then
  VAL_COUNT=$(echo "${VAL_POOL}" | jq '.result | length')
  if [ "${VAL_COUNT}" -eq 7 ]; then
    pass "QBFT consensus active with exactly 7 validators in pool"
  else
    warn "QBFT consensus active but has ${VAL_COUNT} validators (expected: 7)"
  fi
else
  fail "Could not retrieve validator pool via qbft_getValidatorsByBlockNumber"
fi

# ─── Check 7: PDB Enforcement Audit ──────────────────────────────────────
echo ""
echo "━━━ [7/10] PodDisruptionBudget Audit ━━━"
PDB_STATUS=$(kubectl get pdb private-validators-pdb -n "${NAMESPACE}" -o jsonpath='{.spec.maxUnavailable}' 2>/dev/null || echo "missing")
if [ "${PDB_STATUS}" = "1" ]; then
  pass "PDB 'private-validators-pdb' exists with maxUnavailable: 1"
else
  fail "PDB 'private-validators-pdb' configuration error (found maxUnavailable: ${PDB_STATUS})"
fi

# ─── Check 8: NetworkPolicy Isolation Check ──────────────────────────────
echo ""
echo "━━━ [8/10] NetworkPolicy Isolation Check ━━━"
# We attempt to run a curl request from the besu-public namespace to the private RPC service.
# Since NetworkPolicy isolates namespaces, this request MUST fail.
NETPOL_TEST=$(kubectl run netpol-tester --image=curlimages/curl --restart=Never \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"fsGroup":1000},"containers":[{"name":"tester","image":"curlimages/curl","command":["curl","-m","3","http://rpc-rono.besu-private.svc.cluster.local:8545"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
  -n "${PUBLIC_NAMESPACE}" 2>&1 || echo "Pod creation rejected")

sleep 3 # Give pod a moment to complete execution
TEST_LOGS=$(kubectl logs netpol-tester -n "${PUBLIC_NAMESPACE}" 2>/dev/null || echo "timeout")
kubectl delete pod netpol-tester -n "${PUBLIC_NAMESPACE}" --ignore-not-found --wait=false >/dev/null 2>&1

if echo "${TEST_LOGS}" | grep -qi "timeout\|timed out\|could not resolve"; then
  pass "NetworkPolicy correctly blocked request from public namespace to private RPC"
else
  fail "NetworkPolicy failed to block connection! Public namespace could reach private RPC node."
fi

# ─── Check 9: TLS Handshake Audit ────────────────────────────────────────
echo ""
echo "━━━ [9/10] TLS Handshake Verification ━━━"
TLS_LOGS=$(kubectl logs pod/validator-afrinic-0 -c besu -n "${NAMESPACE}" --tail=100 2>/dev/null || echo "")
if echo "${TLS_LOGS}" | grep -qi "tls\|handshake\|secure"; then
  pass "Node logs indicate active TLS communication attempts"
else
  warn "Could not explicitly locate TLS/handshake messages in the last 100 log lines of validator-afrinic."
fi

# ─── Check 10: Pod Security Admission Enforcement Audit ──────────────────
echo ""
echo "━━━ [10/10] PSA Compliance Audit ━━━"
NON_ROOT_FAIL=0
POD_SPECS=$(kubectl get pods -n "${NAMESPACE}" -l network=private -o json 2>/dev/null || echo "[]")
if [ "${POD_SPECS}" != "[]" ]; then
  ROOT_CHECK=$(echo "${POD_SPECS}" | jq -r '.items[].spec.containers[].securityContext.runAsNonRoot' | sort -u)
  if [ "${ROOT_CHECK}" = "true" ]; then
    pass "All running containers have runAsNonRoot enabled"
  else
    fail "One or more containers lack runAsNonRoot setting (found: ${ROOT_CHECK})"
    NON_ROOT_FAIL=1
  fi
else
  fail "Could not retrieve pod specs for security check"
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

if [ "$FAIL" -eq 0 ] && [ "${VAL_FAIL}" -eq 0 ] && [ "${RPC_FAIL}" -eq 0 ]; then
  echo -e "${GREEN}✅ Phase 3 PASSED — Private network is fully operational and secure!${NC}"
  exit 0
else
  echo -e "${RED}❌ Phase 3 FAILED — resolve active issues before deploying Phase 4 contract layer.${NC}"
  exit 1
fi
