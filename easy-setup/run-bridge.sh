#!/bin/bash
# ========================
# Bridge Setup (Phase 7)
# Deploys the anchor-service CronJob that connects private and public networks
#
# Usage: bash run-bridge.sh
# Prerequisites: Both private and public networks must be running
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config.env"

echo "╔══════════════════════════════════════════════╗"
echo "║   Bridge Setup (besu-app)                    ║"
echo "╚══════════════════════════════════════════════╝"

echo ""
echo "Step 1/1: Centralized Bridge and Relayer deployment..."
bash "${SCRIPT_DIR}/../bridge/deploy_bridge.sh"

echo ""
echo "✅ Bridge setup complete (or skipped steps for later phases)"
