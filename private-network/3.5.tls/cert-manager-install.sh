#!/bin/bash
# ========================
# Idempotent cert-manager Installer
#
# Installs cert-manager into the cluster to enable automated internal CA
# and TLS keystore management.
# ========================

set -euo pipefail

echo "Checking if cert-manager is already installed..."
if kubectl get deployment cert-manager -n cert-manager >/dev/null 2>&1; then
  echo "✅ cert-manager is already installed."
  exit 0
fi

echo "Installing cert-manager (v1.17.1)..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.1/cert-manager.yaml

echo "Waiting for cert-manager deployments to become ready..."
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=180s
kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=180s
kubectl wait --for=condition=Available deployment/cert-manager-cainjector -n cert-manager --timeout=180s

echo "✅ cert-manager successfully installed and ready!"
