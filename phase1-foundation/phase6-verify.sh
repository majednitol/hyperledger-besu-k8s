#!/bin/bash
# ========================
# Phase 6 Verification Script
# Verifies that public bootnodes, validators (PDB spread), RPC autoscalers,
# Ingress routing, and NetworkPolicy namespace isolation are fully operational.
#
# Usage: bash phase6-verify.sh
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
echo "║   Phase 6 — Public Network Verification      ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

NAMESPACE="${PUBLIC_NAMESPACE}"

# ─── Check 1: Verify Bootnode LoadBalancers ──────────────────────────────
echo "━━━ [1/10] Public Bootnode Services ━━━"
BOOT_ERR=0
for i in $(seq 1 "${PUBLIC_BOOTNODE_COUNT}"); do
  NAME="public-bootnode-${i}"
  if kubectl get svc "${NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    SVC_TYPE=$(kubectl get svc "${NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
    if [ "${SVC_TYPE}" = "LoadBalancer" ]; then
      pass "Service '${NAME}' is active with type LoadBalancer"
    else
      fail "Service '${NAME}' exists but type is '${SVC_TYPE}' (expected: LoadBalancer)"
      BOOT_ERR=$((BOOT_ERR + 1))
    fi
  else
    fail "Service '${NAME}' is missing"
    BOOT_ERR=$((BOOT_ERR + 1))
  fi
done

# ─── Check 2: Verify 5 Validator StatefulSets ────────────────────────────
echo ""
echo "━━━ [2/10] Public Validator StatefulSets ━━━"
VAL_ERR=0
for i in $(seq 1 "${PUBLIC_VALIDATOR_COUNT}"); do
  NAME="public-validator-${i}"
  if kubectl get statefulset "${NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    REPLICAS=$(kubectl get statefulset "${NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [ "${REPLICAS}" -eq 1 ]; then
      pass "StatefulSet '${NAME}' exists with 1 replica"
    else
      fail "StatefulSet '${NAME}' exists but replicas = ${REPLICAS} (expected: 1)"
      VAL_ERR=$((VAL_ERR + 1))
    fi
  else
    fail "StatefulSet '${NAME}' is missing"
    VAL_ERR=$((VAL_ERR + 1))
  fi
done

# ─── Check 3: Verify Validator PDB ───────────────────────────────────────
echo ""
echo "━━━ [3/10] Public Validators PDB ━━━"
if kubectl get pdb public-validators-pdb -n "${NAMESPACE}" >/dev/null 2>&1; then
  MAX_UNAVAIL=$(kubectl get pdb public-validators-pdb -n "${NAMESPACE}" -o jsonpath='{.spec.maxUnavailable}' 2>/dev/null || echo "")
  if [ "${MAX_UNAVAIL}" = "1" ]; then
    pass "PDB 'public-validators-pdb' active with maxUnavailable: 1"
  else
    fail "PDB 'public-validators-pdb' exists but maxUnavailable = '${MAX_UNAVAIL}' (expected: 1)"
  fi
else
  fail "PDB 'public-validators-pdb' is missing"
fi

# ─── Check 4: Verify RPC Deployment ──────────────────────────────────────
echo ""
echo "━━━ [4/10] Public RPC Deployment ━━━"
if kubectl get deployment public-rpc -n "${NAMESPACE}" >/dev/null 2>&1; then
  REPLICAS=$(kubectl get deployment public-rpc -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
  if [ "${REPLICAS}" -ge 3 ]; then
    pass "Deployment 'public-rpc' is active with ${REPLICAS} replicas (minimum: 3)"
  else
    fail "Deployment 'public-rpc' active but has only ${REPLICAS} replicas (expected: 3+)"
  fi
else
  fail "Deployment 'public-rpc' is missing"
fi

# ─── Check 5: Verify RPC HPA Autoscaler ──────────────────────────────────
echo ""
echo "━━━ [5/10] Public RPC HPA Autoscaler ━━━"
if kubectl get hpa public-rpc-hpa -n "${NAMESPACE}" >/dev/null 2>&1; then
  MIN_R=$(kubectl get hpa public-rpc-hpa -n "${NAMESPACE}" -o jsonpath='{.spec.minReplicas}' 2>/dev/null || echo "0")
  MAX_R=$(kubectl get hpa public-rpc-hpa -n "${NAMESPACE}" -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo "0")
  TARGET_CPU=$(kubectl get hpa public-rpc-hpa -n "${NAMESPACE}" -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}' 2>/dev/null || echo "0")
  
  if [ "${MIN_R}" -eq 3 ] && [ "${MAX_R}" -eq 8 ] && [ "${TARGET_CPU}" -eq 65 ]; then
    pass "HPA 'public-rpc-hpa' configured correctly (Min: ${MIN_R}, Max: ${MAX_R}, Target CPU: ${TARGET_CPU}%)"
  else
    warn "HPA 'public-rpc-hpa' properties do not match plan: Min=${MIN_R}, Max=${MAX_R}, CPU=${TARGET_CPU}%"
  fi
else
  fail "HPA 'public-rpc-hpa' is missing"
fi

# ─── Check 6: Check RPC exposed API namespaces ───────────────────────────
echo ""
echo "━━━ [6/10] RPC exposed API configuration ━━━"
if kubectl get deployment public-rpc -n "${NAMESPACE}" >/dev/null 2>&1; then
  RPC_APIS=$(kubectl get deployment public-rpc -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null || echo "")
  
  if echo "${RPC_APIS}" | grep -q "rpc-http-api"; then
    ENABLED_APIS=$(echo "${RPC_APIS}" | grep -oE "\-\-rpc\-http\-api=[A-Z,]+" | cut -d= -f2 || echo "")
    if [[ "${ENABLED_APIS}" =~ "ADMIN" ]] || [[ "${ENABLED_APIS}" =~ "TXPOOL" ]] || [[ "${ENABLED_APIS}" =~ "DEBUG" ]]; then
      fail "SECURITY ALERT: Unsafe APIs exposed on public RPC: ${ENABLED_APIS}!"
    elif [ "${ENABLED_APIS}" = "ETH,NET,QBFT,WEB3" ]; then
      pass "RPC HTTP API namespace is restricted to safe set (${ENABLED_APIS})"
    else
      warn "RPC HTTP API namespace is set to non-standard: ${ENABLED_APIS}"
    fi
  else
    fail "RPC config is missing explicit --rpc-http-api argument"
  fi
else
  fail "Skipping API namespace checks (Deployment public-rpc missing)"
fi

# ─── Check 7: Verify Ingress configuration ───────────────────────────────
echo ""
echo "━━━ [7/10] Ingress Configuration ━━━"
if kubectl get ingress public-network-ingress -n "${NAMESPACE}" >/dev/null 2>&1; then
  INGRESS_CLASS=$(kubectl get ingress public-network-ingress -n "${NAMESPACE}" -o jsonpath='{.metadata.annotations.kubernetes\.io/ingress\.class}' 2>/dev/null || echo "")
  ISSUER=$(kubectl get ingress public-network-ingress -n "${NAMESPACE}" -o jsonpath='{.metadata.annotations.cert-manager\.io/cluster-issuer}' 2>/dev/null || echo "")
  
  if [ "${INGRESS_CLASS}" = "nginx" ] && [ "${ISSUER}" = "letsencrypt-prod" ]; then
    pass "Public Ingress has correct annotations (class: ${INGRESS_CLASS}, issuer: ${ISSUER})"
  else
    warn "Public Ingress has unexpected annotations: class='${INGRESS_CLASS}', issuer='${ISSUER}'"
  fi
else
  fail "Ingress 'public-network-ingress' is missing"
fi

# ─── Check 8: Verify Network Policy Presence ─────────────────────────────
echo ""
echo "━━━ [8/10] NetworkPolicy Configuration ━━━"
if kubectl get netpol default-deny-all -n "${NAMESPACE}" >/dev/null 2>&1; then
  pass "default-deny-all policy is applied in '${NAMESPACE}'"
else
  fail "default-deny-all policy is missing in '${NAMESPACE}'"
fi

# ─── Check 9: Verify Private Network Isolation ───────────────────────────
echo ""
echo "━━━ [9/10] Namespace Isolation Verification ━━━"
echo "   Launching a helper pod in public namespace to attempt connection to private RPC..."
kubectl run isolation-test-helper -n "${NAMESPACE}" --image=alpine --restart=Never \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"fsGroup":1000},"containers":[{"name":"test","image":"alpine","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
  -- sleep 10 >/dev/null 2>&1 || true

sleep 2

# Try connecting to private RPC. It should time out/fail due to NetworkPolicy
if kubectl exec -n "${NAMESPACE}" isolation-test-helper -- nc -w 3 -z "rpc-rono.${PRIVATE_NAMESPACE}.svc.cluster.local" 8545 >/dev/null 2>&1; then
  fail "SECURITY BREACH: Public namespace pod can reach private RPC endpoint! Check NetworkPolicy configuration."
else
  pass "Isolation Confirmed: Public pod cannot reach private network RPC (Connection blocked)"
fi

# Cleanup
kubectl delete pod isolation-test-helper -n "${NAMESPACE}" --wait=false >/dev/null 2>&1 || true

# ─── Check 10: Block Production Progression ──────────────────────────────
echo ""
echo "━━━ [10/10] Block Production Check ━━━"
RPC_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=public-rpc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "${RPC_POD}" ]; then
  BLOCK1=$(kubectl exec -n "${NAMESPACE}" "${RPC_POD}" -c besu -- \
    curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 2>/dev/null | jq -r '.result' || echo "")
  
  if [ -n "${BLOCK1}" ] && [ "${BLOCK1}" != "null" ]; then
    VAL1=$(printf "%d" "${BLOCK1}")
    echo "   Initial block height: ${VAL1}"
    echo "   Waiting 10 seconds for block progression..."
    sleep 10
    BLOCK2=$(kubectl exec -n "${NAMESPACE}" "${RPC_POD}" -c besu -- \
      curl -s -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
      http://localhost:8545 2>/dev/null | jq -r '.result' || echo "")
    
    if [ -n "${BLOCK2}" ] && [ "${BLOCK2}" != "null" ]; then
      VAL2=$(printf "%d" "${BLOCK2}")
      echo "   Subsequent block height: ${VAL2}"
      if [ "${VAL2}" -gt "${VAL1}" ]; then
        pass "Public network is producing blocks (height progressed from ${VAL1} to ${VAL2})"
      else
        warn "Public block height did not progress (stayed at ${VAL1}). Confirm validators are peering."
      fi
    else
      fail "Failed to query subsequent block height"
    fi
  else
    warn "Failed to query initial block height (expected if nodes have not finished synchronization)"
  fi
else
  warn "public-rpc pod not running; skipping block production check"
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

if [ "$FAIL" -eq 0 ] && [ "${BOOT_ERR}" -eq 0 ] && [ "${VAL_ERR}" -eq 0 ]; then
  echo -e "${GREEN}✅ Phase 6 PASSED — all public nodes, HPA scaling, ingress, and isolation policies active!${NC}"
  exit 0
else
  echo -e "${RED}❌ Phase 6 FAILED — resolve issues before deploying bridge anchoring in Phase 7.${NC}"
  exit 1
fi
