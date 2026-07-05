#!/bin/bash
# ========================
# Public Network Setup (Phases 5–6)
# Deploys the public open Besu network: genesis, nodes, ingress, network policy
#
# Usage: bash run-public.sh
# Prerequisites: Phase 1 complete (namespaces, RBAC, config.env)
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "╔══════════════════════════════════════════════╗"
echo "║   Public Network Setup (besu-public)         ║"
echo "╚══════════════════════════════════════════════╝"

echo ""
echo "Step 1/6: Storage (PV/PVC)..."
kubectl apply -n "$PUBLIC_NAMESPACE" -f "${SCRIPT_DIR}/../public-network/1.storage/pvc.yaml"

echo "Step 2/6: Genesis generation..."
kubectl apply -n "$PUBLIC_NAMESPACE" -f "${SCRIPT_DIR}/../public-network/2.genesis/generate-genesis-job.yaml"

echo "   Waiting for generate-public-genesis Job to complete..."
kubectl wait --for=condition=complete job/generate-public-genesis -n "$PUBLIC_NAMESPACE" --timeout=120s

echo "   Extracting keys and creating ConfigMaps..."
bash "${SCRIPT_DIR}/../public-network/2.genesis/extract-keys.sh"

echo "Step 3/6: ConfigMaps template check..."
echo "  → ConfigMaps already created and applied during Step 2 key extraction."

echo "Step 3.5/6: TLS Ingress Issuers..."
kubectl apply -f "${SCRIPT_DIR}/../public-network/8.ingress/letsencrypt-issuer.yaml"

echo "Step 4/6: Bootnodes..."
if [ -f "${SCRIPT_DIR}/../public-network/4.bootnodes/deploy_public_bootnode.sh" ]; then
  bash "${SCRIPT_DIR}/../public-network/4.bootnodes/deploy_public_bootnode.sh"
else
  echo "  → No bootnode script yet (Phase 6)"
fi

echo "Step 5/6: Validators..."
if [ -f "${SCRIPT_DIR}/../public-network/5.validators/deploy_public_validators.sh" ]; then
  bash "${SCRIPT_DIR}/../public-network/5.validators/deploy_public_validators.sh"
else
  echo "  → No validator script yet (Phase 6)"
fi

echo "Step 6/6: RPC nodes + Ingress + Network Policy..."
if [ -f "${SCRIPT_DIR}/../public-network/6.rpc-nodes/deploy_public_rpc.sh" ]; then
  bash "${SCRIPT_DIR}/../public-network/6.rpc-nodes/deploy_public_rpc.sh"
else
  echo "  → No RPC node script yet (Phase 6)"
fi
kubectl apply -n "$PUBLIC_NAMESPACE" -f "${SCRIPT_DIR}/../public-network/8.ingress/" 2>/dev/null || echo "  → No ingress manifests yet (Phase 6)"
kubectl apply -n "$PUBLIC_NAMESPACE" -f "${SCRIPT_DIR}/../public-network/9.network-policy/" 2>/dev/null || echo "  → No network policy yet (Phase 6)"

echo ""
echo "✅ Public network setup complete (or skipped steps for later phases)"
