#!/bin/bash
# ========================
# Full Deployment Orchestrator
# Runs all setup scripts in order: Phase 1 verify → Private → Public → Bridge → App Layer
#
# Usage: bash run.sh
# Prerequisites: Phase 1 must be complete (run phase1-verify.sh first)
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "╔══════════════════════════════════════════════════════╗"
echo "║   Besu Dual-Network Full Deployment Orchestrator    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ─── Pre-flight: Phase 1 verification ───────────────────────────────────
echo "━━━ Pre-flight: Phase 1 Verification ━━━"
if bash "${SCRIPT_DIR}/../phase1-foundation/phase1-verify.sh"; then
  echo ""
  echo "Phase 1 verified. Proceeding with deployment..."
  echo ""
else
  echo ""
  echo "❌ Phase 1 verification failed. Fix issues before running full deployment."
  exit 1
fi

# ─── Private Network (Phases 2–4) ───────────────────────────────────────
echo ""
echo "━━━ [1/5] Private Network ━━━"
bash "${SCRIPT_DIR}/run-private.sh"

# ─── Public Network (Phases 5–6) ────────────────────────────────────────
echo ""
echo "━━━ [2/5] Public Network ━━━"
bash "${SCRIPT_DIR}/run-public.sh"

# ─── Bridge (Phase 7) ───────────────────────────────────────────────────
echo ""
echo "━━━ [3/5] Bridge ━━━"
bash "${SCRIPT_DIR}/run-bridge.sh"

# ─── Application Layer (Phase 8) ────────────────────────────────────────
echo ""
echo "━━━ [4/5] Application Layer ━━━"
echo "Deploying 10.api..."
kubectl apply -n "$APP_NAMESPACE" -f "${SCRIPT_DIR}/../10.api/" 2>/dev/null || echo "  → No API manifests yet (Phase 8)"

echo "Deploying 11.ui..."
kubectl apply -n "$APP_NAMESPACE" -f "${SCRIPT_DIR}/../11.ui/" 2>/dev/null || echo "  → No UI manifests yet (Phase 8)"

echo "Deploying 12.explorer (private)..."
kubectl apply -n "$PRIVATE_NAMESPACE" -f "${SCRIPT_DIR}/../12.explorer/explorer-private/" 2>/dev/null || echo "  → No private explorer yet (Phase 8)"

echo "Deploying 12.explorer (public)..."
kubectl apply -n "$PUBLIC_NAMESPACE" -f "${SCRIPT_DIR}/../12.explorer/explorer-public/" 2>/dev/null || echo "  → No public explorer yet (Phase 8)"

# ─── Monitoring & Ingress (Phase 9) ─────────────────────────────────────
echo ""
echo "━━━ [5/5] Monitoring & Ingress ━━━"
echo "Deploying 13.monitoring..."
kubectl apply -n "$APP_NAMESPACE" -f "${SCRIPT_DIR}/../13.monitoring/" 2>/dev/null || echo "  → No monitoring manifests yet (Phase 9)"

echo "Deploying 14.ingress..."
kubectl apply -f "${SCRIPT_DIR}/../14.ingress/" 2>/dev/null || echo "  → No top-level ingress yet (Phase 9)"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║   ✅ Full deployment orchestration complete          ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "  1. Verify private network: kubectl exec -it validator-afrinic-0 -n besu-private -- besu --help"
echo "  2. Verify public network:  curl -X POST https://rpc.public.<domain> -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_chainId\",\"params\":[],\"id\":1}'"
echo "  3. Verify bridge:          kubectl logs -n besu-app job/registry-anchor"
echo "  4. Open Grafana:           kubectl port-forward -n besu-app svc/grafana 3000:3000"
