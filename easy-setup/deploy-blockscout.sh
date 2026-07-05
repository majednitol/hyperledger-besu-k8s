#!/bin/bash
# ========================
# Deploy Blockscout Block Explorer
# Automates the deployment of PostgreSQL, Redis, and Blockscout engine.
#
# Usage: bash deploy-blockscout.sh
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Deploying Blockscout Explorer stack..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1. Apply auxiliary services (Postgres, Redis)
echo -e "${YELLOW}Applying Postgres and Redis deployments...${NC}"
kubectl apply -f "${SCRIPT_DIR}/../14.blockscout/blockscout-services.yaml"

# 2. Wait for Postgres database readiness
echo -e "${YELLOW}Waiting for blockscout-db pod rollout...${NC}"
kubectl rollout status deployment/blockscout-db -n besu-app --timeout=120s

# 3. Apply Blockscout Monolith application
echo -e "${YELLOW}Applying Blockscout application and Ingress...${NC}"
kubectl apply -f "${SCRIPT_DIR}/../14.blockscout/blockscout-app.yaml"

# 4. Wait for Blockscout engine to roll out
echo -e "${YELLOW}Waiting for blockscout application pod rollout...${NC}"
kubectl rollout status deployment/blockscout -n besu-app --timeout=180s

echo ""
echo -e "${GREEN}✅ Blockscout Stack deployed successfully!${NC}"
echo "--------------------------------------------------"
echo "To access Blockscout locally, run:"
echo "  kubectl port-forward svc/blockscout 4000:4000 -n besu-app"
echo "Then navigate to:"
echo "  http://localhost:4000"
echo "--------------------------------------------------"
echo "If deploying in production, ensure your Ingress domain"
echo "  'explorer.yourdomain.com' is mapped to your LoadBalancer."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
