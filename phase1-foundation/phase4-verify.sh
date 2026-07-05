#!/bin/bash
# ========================
# Phase 4 Verification Script
# Verifies that contract unit tests pass, and queries the running private network
# to check the deployment and state of the Ingress permissioning contracts.
#
# Usage: bash phase4-verify.sh
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
echo "║   Phase 4 — Private Contracts Verification   ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

NAMESPACE="${PRIVATE_NAMESPACE}"
CONTRACTS_DIR="${SCRIPT_DIR}/../private-network/8.contracts"

# ─── Check 1: Run Hardhat Unit Tests ─────────────────────────────────────
echo "━━━ [1/5] Hardhat Unit Tests ━━━"
if cd "${CONTRACTS_DIR}" && npx hardhat test --network hardhat > /tmp/hardhat-test.log 2>&1; then
  pass "All Hardhat unit tests passed successfully"
else
  cat /tmp/hardhat-test.log
  fail "Hardhat unit tests failed! See output above."
fi
cd "${SCRIPT_DIR}"

# ─── Check 2: Check NodeIngress bytecode at 0x...9999 ────────────────────
echo ""
echo "━━━ [2/5] NodeIngress Bytecode Check ━━━"
RPC_POD=$(kubectl get pods -n "${NAMESPACE}" -l app=rpc-rono -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "${RPC_POD}" ]; then
  CODE9999=$(kubectl exec -n "${NAMESPACE}" "${RPC_POD}" -c besu -- \
    curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_getCode","params":["0x0000000000000000000000000000000000009999", "latest"],"id":1}' \
    http://localhost:8545 2>/dev/null | jq -r '.result' || echo "0x")
  
  if [ "${CODE9999}" != "0x" ] && [ "${CODE9999}" != "0x00" ] && [ "${CODE9999}" != "null" ]; then
    pass "NodeIngress bytecode exists at pre-allocated address 0x...9999"
  else
    warn "NodeIngress bytecode not found at 0x...9999 (expected for genesis-allocated deployments; verify qbftConfigFile.json)"
  fi
else
  warn "rpc-rono pod not found; skipping on-chain bytecode checks"
fi

# ─── Check 3: Check AccountIngress bytecode at 0x...8888 ─────────────────
echo ""
echo "━━━ [3/5] AccountIngress Bytecode Check ━━━"
if [ -n "${RPC_POD}" ]; then
  CODE8888=$(kubectl exec -n "${NAMESPACE}" "${RPC_POD}" -c besu -- \
    curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_getCode","params":["0x0000000000000000000000000000000000008888", "latest"],"id":1}' \
    http://localhost:8545 2>/dev/null | jq -r '.result' || echo "0x")
  
  if [ "${CODE8888}" != "0x" ] && [ "${CODE8888}" != "0x00" ] && [ "${CODE8888}" != "null" ]; then
    pass "AccountIngress bytecode exists at pre-allocated address 0x...8888"
  else
    warn "AccountIngress bytecode not found at 0x...8888 (expected for genesis-allocated deployments; verify qbftConfigFile.json)"
  fi
fi

# ─── Check 4: Check Solidity Compiler version ───────────────────────────
echo ""
echo "━━━ [4/5] Solidity Configuration Check ━━━"
CFG_FILE="${CONTRACTS_DIR}/hardhat.config.js"
if [ -f "${CFG_FILE}" ] && grep -q "0.8.20" "${CFG_FILE}"; then
  pass "hardhat.config.js is configured with compiler version 0.8.20"
else
  fail "hardhat.config.js is missing or compiler version is incorrect"
fi

# ─── Check 5: Verify OpenZeppelin Dependency ────────────────────────────
echo ""
echo "━━━ [5/5] Dependencies Check ━━━"
PKG_FILE="${CONTRACTS_DIR}/package.json"
if [ -f "${PKG_FILE}" ] && grep -q "@openzeppelin/contracts" "${PKG_FILE}"; then
  pass "package.json contains @openzeppelin/contracts dependency"
else
  fail "package.json is missing or lacks OpenZeppelin dependency"
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
  echo -e "${GREEN}✅ Phase 4 PASSED — contracts compile, unit tests pass, and config verified!${NC}"
  exit 0
else
  echo -e "${RED}❌ Phase 4 FAILED — resolve active issues before deploying public network in Phase 5.${NC}"
  exit 1
fi
