#!/bin/bash
# ========================
# Phase 1 Verification Script
# Run after applying all Phase 1 manifests to confirm exit conditions.
#
# Usage: bash phase1-verify.sh
# Exit codes: 0 = all checks pass, 1 = critical failure
# ========================

set -euo pipefail

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

# Colors for output
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
echo "║   Phase 1 — Foundation Verification Script   ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ─── Check 1: Kubernetes connectivity ────────────────────────────────────
echo "━━━ [1/8] Kubernetes Connectivity ━━━"
if kubectl cluster-info > /dev/null 2>&1; then
  KUBE_VERSION=$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' 2>/dev/null || echo "unknown")
  pass "kubectl connected (client: $KUBE_VERSION)"
else
  fail "kubectl not connected — cannot proceed"
  echo ""
  echo "Debugging: Run 'kubectl cluster-info' to diagnose connectivity."
  exit 1
fi

# Check K8s server version (PSA requires >= 1.25)
SERVER_MINOR=$(kubectl version -o json 2>/dev/null | jq -r '.serverVersion.minor // "0"' | tr -d '+')
if [ "${SERVER_MINOR:-0}" -ge 25 ] 2>/dev/null; then
  pass "K8s server version 1.${SERVER_MINOR} (>= 1.25 required for PSA GA)"
else
  warn "K8s server version 1.${SERVER_MINOR} — PSA may not be GA; verify manually"
fi

# ─── Check 2: Namespaces exist with PSA labels ──────────────────────────
echo ""
echo "━━━ [2/8] Namespaces & Pod Security Admission ━━━"
for NS in "$PRIVATE_NAMESPACE" "$PUBLIC_NAMESPACE" "$APP_NAMESPACE"; do
  if kubectl get ns "$NS" > /dev/null 2>&1; then
    # Check PSA enforce label
    PSA_LABEL=$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
    if [ "$PSA_LABEL" = "restricted" ]; then
      pass "$NS exists with PSA enforce=restricted"
    else
      fail "$NS exists but PSA enforce label is '${PSA_LABEL:-missing}' (expected: restricted)"
    fi

    # Check metadata.name label (needed for NetworkPolicy namespaceSelector)
    NAME_LABEL=$(kubectl get ns "$NS" -o jsonpath='{.metadata.labels.kubernetes\.io/metadata\.name}' 2>/dev/null)
    if [ "$NAME_LABEL" = "$NS" ]; then
      pass "$NS has kubernetes.io/metadata.name label"
    else
      warn "$NS missing kubernetes.io/metadata.name label — NetworkPolicy namespaceSelector may not work"
    fi
  else
    fail "$NS namespace does not exist"
  fi
done

# ─── Check 3: RBAC roles exist ──────────────────────────────────────────
echo ""
echo "━━━ [3/8] RBAC Roles & Bindings ━━━"
declare -A ROLES
ROLES["private-network-operator"]="$PRIVATE_NAMESPACE"
ROLES["public-network-operator"]="$PUBLIC_NAMESPACE"
ROLES["app-layer-deployer"]="$APP_NAMESPACE"

for ROLE in "${!ROLES[@]}"; do
  NS="${ROLES[$ROLE]}"
  if kubectl get role "$ROLE" -n "$NS" > /dev/null 2>&1; then
    pass "Role '$ROLE' exists in $NS"
  else
    fail "Role '$ROLE' missing in $NS"
  fi

  BINDING="${ROLE}-binding"
  if kubectl get rolebinding "$BINDING" -n "$NS" > /dev/null 2>&1; then
    pass "RoleBinding '$BINDING' exists in $NS"
  else
    fail "RoleBinding '$BINDING' missing in $NS"
  fi
done

# ─── Check 4: No rogue cluster-admin bindings ───────────────────────────
echo ""
echo "━━━ [4/8] Cluster-Admin Audit ━━━"
ROGUE=$(kubectl get clusterrolebinding -o json 2>/dev/null | jq -r '
  .items[] | select(.roleRef.name == "cluster-admin") |
  select(.subjects[]? |
    .name != "system:masters" and
    (.name | startswith("system:") | not) and
    (.name | startswith("eks:") | not) and
    (.name | startswith("aks:") | not) and
    (.name | startswith("gke:") | not)
  ) |
  .metadata.name' 2>/dev/null || echo "")

if [ -z "$ROGUE" ]; then
  pass "No non-system cluster-admin bindings found"
else
  warn "Found cluster-admin bindings (review manually): $ROGUE"
fi

# ─── Check 5: config.env validation ─────────────────────────────────────
echo ""
echo "━━━ [5/8] config.env Validation ━━━"

# Chain IDs must differ
if [ "$PRIVATE_CHAIN_ID" != "$PUBLIC_CHAIN_ID" ]; then
  pass "Chain IDs differ (private=$PRIVATE_CHAIN_ID, public=$PUBLIC_CHAIN_ID)"
else
  fail "Chain IDs must differ! Both are $PRIVATE_CHAIN_ID"
fi

# Chain IDs must not collide with known public chains
KNOWN_CHAIN_IDS=(1 5 11155111 137 56 42161 10)  # Mainnet, Goerli, Sepolia, Polygon, BSC, Arbitrum, Optimism
for KID in "${KNOWN_CHAIN_IDS[@]}"; do
  if [ "$PRIVATE_CHAIN_ID" = "$KID" ] || [ "$PUBLIC_CHAIN_ID" = "$KID" ]; then
    fail "Chain ID $KID collides with a known public chain!"
  fi
done
pass "Chain IDs don't collide with known public chains"

# Org count
if [ "${#ORG_NAMES[@]}" -eq 6 ]; then
  pass "6 organizations defined: ${ORG_NAMES[*]}"
else
  warn "Expected 6 orgs, found ${#ORG_NAMES[@]}: ${ORG_NAMES[*]}"
fi

# Besu image not :latest
if [[ "$BESU_IMAGE" == *":latest"* ]]; then
  fail "BESU_IMAGE uses :latest tag — pin to a specific version"
else
  pass "BESU_IMAGE is version-pinned: $BESU_IMAGE"
fi

# ─── Check 6: PSA enforcement test ──────────────────────────────────────
echo ""
echo "━━━ [6/8] PSA Enforcement Test ━━━"
PSA_TEST_OUTPUT=$(kubectl run psa-test-phase1 --image=busybox --restart=Never \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "test",
        "image": "busybox",
        "command": ["sleep", "1"],
        "securityContext": {"privileged": true}
      }]
    }
  }' \
  -n "$PRIVATE_NAMESPACE" 2>&1 || true)

if echo "$PSA_TEST_OUTPUT" | grep -qi "forbidden\|violat\|denied"; then
  pass "PSA correctly rejects privileged pods in $PRIVATE_NAMESPACE"
else
  kubectl delete pod psa-test-phase1 -n "$PRIVATE_NAMESPACE" --ignore-not-found > /dev/null 2>&1
  fail "PSA did NOT reject a privileged pod — enforcement may not be active"
fi

# ─── Check 7: Directory scaffold ────────────────────────────────────────
echo ""
echo "━━━ [7/8] Directory Scaffold ━━━"
REQUIRED_DIRS=(
  "private-network/1.storage"
  "private-network/2.genesis"
  "private-network/3.configmap"
  "private-network/3.5.tls"
  "private-network/4.bootnodes"
  "private-network/5.validators"
  "private-network/6.rpc-nodes"
  "private-network/7.privacy"
  "private-network/8.contracts"
  "private-network/9.network-policy"
  "public-network/1.storage"
  "public-network/2.genesis"
  "public-network/3.configmap"
  "public-network/4.bootnodes"
  "public-network/5.validators"
  "public-network/6.rpc-nodes"
  "public-network/7.contracts"
  "public-network/8.ingress"
  "public-network/9.network-policy"
  "bridge/anchor-service/src"
  "10.api"
  "11.ui"
  "12.explorer/explorer-private"
  "12.explorer/explorer-public"
  "13.monitoring"
  "14.ingress"
  "easy-setup"
)

MISSING_DIRS=0
for DIR in "${REQUIRED_DIRS[@]}"; do
  FULL_PATH="${SCRIPT_DIR}/../${DIR}"
  if [ -d "$FULL_PATH" ]; then
    pass "$DIR"
  else
    fail "Missing: $DIR"
    ((MISSING_DIRS++)) || true
  fi
done

# ─── Check 8: Documentation completeness ────────────────────────────────
echo ""
echo "━━━ [8/8] Phase 1 Documentation ━━━"
REQUIRED_DOCS=(
  "phase1-foundation/capacity-plan.md"
  "phase1-foundation/decisions.md"
  "phase1-foundation/api-design.md"
  "phase1-foundation/frontend-design.md"
)

for DOC in "${REQUIRED_DOCS[@]}"; do
  FULL_PATH="${SCRIPT_DIR}/../${DOC}"
  if [ -f "$FULL_PATH" ]; then
    LINES=$(wc -l < "$FULL_PATH")
    pass "$DOC ($LINES lines)"
  else
    fail "Missing: $DOC"
  fi
done

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
  echo -e "${GREEN}✅ Phase 1 PASSED — ready to proceed to Phase 2${NC}"
  exit 0
else
  echo -e "${RED}❌ Phase 1 FAILED — fix $FAIL issue(s) before proceeding${NC}"
  echo ""
  echo "Debugging tips:"
  echo "  1. Check 'kubectl get ns --show-labels' for namespace issues"
  echo "  2. Check 'kubectl get roles -A' for RBAC issues"
  echo "  3. Check K8s version with 'kubectl version' for PSA support"
  echo "  4. Review config.env for chain ID or image tag issues"
  exit 1
fi
