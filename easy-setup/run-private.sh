#!/bin/bash
# ========================
# Private Network Setup (Phases 2–4)
# Deploys the private permissioned Besu network: genesis, keys, TLS, nodes, contracts
#
# Usage: bash run-private.sh
# Prerequisites: Phase 1 complete (namespaces, RBAC, config.env)
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "╔══════════════════════════════════════════════╗"
echo "║   Private Network Setup (besu-private)       ║"
echo "╚══════════════════════════════════════════════╝"

echo ""
echo "Step 1/6: Storage (PV/PVC)..."
if [ -f "${SCRIPT_DIR}/minikube-storage.yaml" ]; then
  echo "  Applying local PersistentVolumes for Minikube hostPath mount..."
  kubectl apply -f "${SCRIPT_DIR}/minikube-storage.yaml"
fi
kubectl apply -n "$PRIVATE_NAMESPACE" -f "${SCRIPT_DIR}/../private-network/1.storage/pvc.yaml"

echo "Step 2/6: Genesis generation..."
kubectl apply -n "$PRIVATE_NAMESPACE" -f "${SCRIPT_DIR}/../private-network/2.genesis/generate-genesis-job.yaml"

echo "   Waiting for generate-genesis Job to complete..."
kubectl wait --for=condition=complete job/generate-genesis -n "$PRIVATE_NAMESPACE" --timeout=120s

echo "   Extracting keys and creating ConfigMaps..."
bash "${SCRIPT_DIR}/../private-network/2.genesis/extract-keys.sh"

echo "Step 3/6: ConfigMaps template check..."
echo "  → ConfigMaps already created and applied during Step 2 key extraction."

echo "Step 3.5/6: TLS certificates..."
bash "${SCRIPT_DIR}/../private-network/3.5.tls/cert-manager-install.sh"
bash "${SCRIPT_DIR}/../private-network/3.5.tls/generate-tls-certs.sh"

echo "Step 4/6: Bootnodes..."
if [ -f "${SCRIPT_DIR}/../private-network/4.bootnodes/deploy_bootnodes.sh" ]; then
  bash "${SCRIPT_DIR}/../private-network/4.bootnodes/deploy_bootnodes.sh"
else
  echo "  → No bootnode script yet (Phase 3)"
fi

echo "Step 5/6: Validators..."
if [ -f "${SCRIPT_DIR}/../private-network/5.validators/deploy_validators.sh" ]; then
  bash "${SCRIPT_DIR}/../private-network/5.validators/deploy_validators.sh"
else
  echo "  → No validator script yet (Phase 3)"
fi

echo "Step 6/6: RPC nodes + Network Policy..."
if [ -f "${SCRIPT_DIR}/../private-network/6.rpc-nodes/deploy_rpc_org.sh" ]; then
  bash "${SCRIPT_DIR}/../private-network/6.rpc-nodes/deploy_rpc_org.sh"
else
  echo "  → No RPC node script yet (Phase 3)"
fi
kubectl apply -n "$PRIVATE_NAMESPACE" -f "${SCRIPT_DIR}/../private-network/9.network-policy/" 2>/dev/null || echo "  → No network policy yet (Phase 3)"

echo ""
echo "✅ Private network setup complete (or skipped steps for later phases)"
