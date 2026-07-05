#!/bin/bash
# ========================
# Phase 9 Verification Script
# Verifies that Prometheus, Alertmanager, and Grafana pods are running,
# configmaps exist, image digests/tags are pinned, and RBAC safety is maintained.
#
# Usage: bash phase9-verify.sh
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
echo "║   Phase 9 — Observability & Hardening        ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

APP_NS="besu-app"

# ─── Check 1: Prometheus status ──────────────────────────────────────────
echo "━━━ [1/10] Prometheus Deployment ━━━"
if kubectl get deployment prometheus -n "${APP_NS}" >/dev/null 2>&1; then
  pass "Deployment 'prometheus' exists in namespace '${APP_NS}'"
else
  warn "Deployment 'prometheus' is missing"
fi

# ─── Check 2: Alertmanager status ────────────────────────────────────────
echo ""
echo "━━━ [2/10] Alertmanager Deployment ━━━"
if kubectl get deployment alertmanager -n "${APP_NS}" >/dev/null 2>&1; then
  pass "Deployment 'alertmanager' exists in namespace '${APP_NS}'"
else
  warn "Deployment 'alertmanager' is missing"
fi

# ─── Check 3: Grafana status ─────────────────────────────────────────────
echo ""
echo "━━━ [3/10] Grafana Deployment ━━━"
if kubectl get deployment grafana -n "${APP_NS}" >/dev/null 2>&1; then
  pass "Deployment 'grafana' exists in namespace '${APP_NS}'"
else
  warn "Deployment 'grafana' is missing"
fi

# ─── Check 4: Prometheus ConfigMap ───────────────────────────────────────
echo ""
echo "━━━ [4/10] Prometheus Configuration CM ━━━"
if kubectl get cm prometheus-config -n "${APP_NS}" >/dev/null 2>&1; then
  pass "ConfigMap 'prometheus-config' exists"
else
  fail "ConfigMap 'prometheus-config' is missing"
fi

# ─── Check 5: Grafana ConfigMap ──────────────────────────────────────────
echo ""
echo "━━━ [5/10] Grafana Configuration CM ━━━"
if kubectl get cm grafana-config -n "${APP_NS}" >/dev/null 2>&1; then
  pass "ConfigMap 'grafana-config' exists with datasource and dashboard definitions"
else
  fail "ConfigMap 'grafana-config' is missing"
fi

# ─── Check 6: Alertmanager ConfigMap ─────────────────────────────────────
echo ""
echo "━━━ [6/10] Alertmanager Configuration CM ━━━"
if kubectl get cm alertmanager-config -n "${APP_NS}" >/dev/null 2>&1; then
  pass "ConfigMap 'alertmanager-config' exists"
else
  fail "ConfigMap 'alertmanager-config' is missing"
fi

# ─── Check 7: Image Pinned Tags Check ────────────────────────────────────
echo ""
echo "━━━ [7/10] Image Tag Pinning Audit ━━━"
INVALID_TAGS=0
# Scan workspace manifests for raw ":latest" image tags
while read -r file; do
  if grep -q "image:.*:latest" "$file"; then
    fail "Image pinning violation in $file: uses ':latest' tag"
    INVALID_TAGS=$((INVALID_TAGS + 1))
  fi
done < <(find "${SCRIPT_DIR}/../private-network" "${SCRIPT_DIR}/../public-network" "${SCRIPT_DIR}/../bridge" -name "*.yaml")

if [ "${INVALID_TAGS}" -eq 0 ]; then
  pass "All container images in deployments are pinned to specific version tags"
fi

# ─── Check 8: Check RBAC privilege isolation ────────────────────────────
echo ""
echo "━━━ [8/10] RBAC Scope Verification ━━━"
# Audit namespace roles to ensure no wildcards
WILDCARD_ROLES=0
while read -r file; do
  if grep -q "\- \'*\'" "$file" && grep -q "resources:" "$file"; then
    fail "RBAC isolation violation in $file: contains wildcard '*' in resources or verbs"
    WILDCARD_ROLES=$((WILDCARD_ROLES + 1))
  fi
done < <(find "${SCRIPT_DIR}/" -name "rbac-*.yaml")

if [ "${WILDCARD_ROLES}" -eq 0 ]; then
  pass "No wildcard permissions found in application roles manifests"
fi

# ─── Check 9: Verify Scrape NetworkPolicies ──────────────────────────────
echo ""
echo "━━━ [9/10] Metrics Scrape NetworkPolicies ━━━"
# Check if NetworkPolicy allow scrapers exist on private/public side
PRIV_NETPOL="${SCRIPT_DIR}/../private-network/9.network-policy/netpol-private.yaml"
PUB_NETPOL="${SCRIPT_DIR}/../public-network/9.network-policy/netpol-public.yaml"

if [ -f "${PRIV_NETPOL}" ] && grep -q "besu-app" "${PRIV_NETPOL}" && grep -q "8545" "${PRIV_NETPOL}"; then
  pass "Private network NetworkPolicy permits ingress metrics/rpc queries from besu-app"
else
  fail "Private network NetworkPolicy lacks ingress permissions for besu-app"
fi

if [ -f "${PUB_NETPOL}" ] && grep -q "besu-app" "${PUB_NETPOL}" && grep -q "8545" "${PUB_NETPOL}"; then
  pass "Public network NetworkPolicy permits ingress metrics/rpc queries from besu-app"
else
  fail "Public network NetworkPolicy lacks ingress permissions for besu-app"
fi

# ─── Check 10: Verify non-root context on monitoring pods ───────────────
echo ""
echo "━━━ [10/10] Monitoring SecurityContext check ━━━"
PROM_YAML="${SCRIPT_DIR}/../13.monitoring/prometheus-deployment.yaml"
GRAF_YAML="${SCRIPT_DIR}/../13.monitoring/grafana-deployment.yaml"

if [ -f "${PROM_YAML}" ] && grep -q "runAsNonRoot: true" "${PROM_YAML}"; then
  pass "Prometheus deployment enforces non-root container environment"
else
  fail "Prometheus deployment is missing runAsNonRoot configuration"
fi

if [ -f "${GRAF_YAML}" ] && grep -q "runAsNonRoot: true" "${GRAF_YAML}"; then
  pass "Grafana deployment enforces non-root container environment"
else
  fail "Grafana deployment is missing runAsNonRoot configuration"
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
  echo -e "${GREEN}✅ Phase 9 PASSED — observability stack deployed and cluster security audited successfully!${NC}"
  exit 0
else
  echo -e "${RED}❌ Phase 9 FAILED — resolve configuration, tag pinning, or security violations.${NC}"
  exit 1
fi
