#!/bin/bash
# ========================
# Private Network Key & Configuration Extractor
#
# This script extracts genesis files and keys from the genesis-output-pvc,
# creates Kubernetes Secrets for validator/bootnode/RPC keys,
# and generates the ConfigMaps (genesis.json, static-nodes.json, permissions_config.toml).
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.env"

TEMP_DIR="/tmp/besu-genesis-temp"
NAMESPACE="${PRIVATE_NAMESPACE}"

echo "1. Checking if the generate-genesis Job has completed..."
STATUS=$(kubectl get job generate-genesis -n "${NAMESPACE}" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
if [ "${STATUS}" != "1" ]; then
  echo "  Job 'generate-genesis' has not succeeded yet (status: ${STATUS})."
  echo "  Please apply generate-genesis-job.yaml and wait for it to complete."
  exit 1
fi

echo "2. Spinning up helper pod to extract data from PVC..."
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: Pod
metadata:
  name: genesis-extractor
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: extractor
      image: alpine
      command: ["sleep", "3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      volumeMounts:
        - name: out
          mountPath: /out
  volumes:
    - name: out
      persistentVolumeClaim:
        claimName: genesis-output-pvc
  restartPolicy: Never
EOF

echo "   Waiting for helper pod to be ready..."
kubectl wait --for=condition=Ready pod/genesis-extractor -n "${NAMESPACE}" --timeout=60s

echo "3. Copying generated configuration locally..."
rm -rf "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}"
kubectl cp -n "${NAMESPACE}" genesis-extractor:/out "${TEMP_DIR}"

echo "4. Tearing down helper pod..."
kubectl delete pod genesis-extractor -n "${NAMESPACE}" --wait=false

# Helper arrays/definitions (now sourced from config.env)
# VAL_NAMES and RPC_NAMES are loaded from config.env sourced above

# Check we have the expected directories (fallback for different Besu versions)
if [ -d "${TEMP_DIR}/validators/networkFiles/keys" ]; then
  VAL_DIR="${TEMP_DIR}/validators/networkFiles/keys"
  NON_VAL_DIR="${TEMP_DIR}/non-validators/networkFiles/keys"
  GENESIS_PATH="${TEMP_DIR}/validators/networkFiles/genesis.json"
else
  VAL_DIR="${TEMP_DIR}/validators/keys"
  NON_VAL_DIR="${TEMP_DIR}/non-validators/keys"
  GENESIS_PATH="${TEMP_DIR}/validators/genesis.json"
fi

if [ ! -d "${VAL_DIR}" ] || [ ! -d "${NON_VAL_DIR}" ]; then
  echo "ERROR: Generated directories not found. Check Job logs."
  exit 1
fi

# Get list of sorted directories
cd "${VAL_DIR}"
VAL_KEYS=($(ls -d 0x* | sort))
cd - >/dev/null

cd "${NON_VAL_DIR}"
NON_VAL_KEYS=($(ls -d 0x* | sort))
cd - >/dev/null

echo "5. Verifying key counts..."
EXPECTED_VAL_COUNT="${#VAL_NAMES[@]}"
EXPECTED_NON_VAL_COUNT=$(( ${#RPC_NAMES[@]} + 2 ))

if [ "${#VAL_KEYS[@]}" -ne "${EXPECTED_VAL_COUNT}" ]; then
  echo "ERROR: Expected ${EXPECTED_VAL_COUNT} validator keys, found ${#VAL_KEYS[@]}"
  exit 1
fi
if [ "${#NON_VAL_KEYS[@]}" -ne "${EXPECTED_NON_VAL_COUNT}" ]; then
  echo "ERROR: Expected ${EXPECTED_NON_VAL_COUNT} non-validator keys (2 bootnodes + ${#RPC_NAMES[@]} RPCs), found ${#NON_VAL_KEYS[@]}"
  exit 1
fi

# Create output folder for secrets configuration
SECRETS_OUT="${TEMP_DIR}/secrets-manifests"
mkdir -p "${SECRETS_OUT}"

# Create known-clients.txt temp file for cert-manager
mkdir -p "${TEMP_DIR}/tls-fingerprints"

## 6. Process validator keys
echo "6. Creating Secrets for validators..."
ALL_ENODES=()
ALL_ADDRESSES=()
STATIC_ENODES=()

for i in "${!VAL_NAMES[@]}"; do
  ORG="${VAL_NAMES[$i]}"
  KEY_DIR="${VAL_DIR}/${VAL_KEYS[$i]}"
  NAME="validator-${ORG}"

  # Clean the public key (remove leading 0x if present)
  PUB_KEY=$(cat "${KEY_DIR}/key.pub" | sed 's/^0x//')
  NODE_ADDRESS="${VAL_KEYS[$i]}"
  ALL_ADDRESSES+=("${NODE_ADDRESS}")
  
  # Format enode URL
  ENODE="enode://${PUB_KEY}@${NAME}-0.${NAME}.${NAMESPACE}.svc.cluster.local:30303"
  ALL_ENODES+=("${ENODE}")
  STATIC_ENODES+=("${ENODE}")

  echo "   Validator '${ORG}' -> Address: ${NODE_ADDRESS}"

  # Create K8s Secret manifest
  kubectl create secret generic "${NAME}-key" \
    --from-file=key="${KEY_DIR}/key" \
    --from-file=key.pub="${KEY_DIR}/key.pub" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml > "${SECRETS_OUT}/${NAME}-key.yaml"
  kubectl apply -f "${SECRETS_OUT}/${NAME}-key.yaml"
done

# 7. Process bootnodes (non-validator keys 0 and 1)
echo "7. Creating Secrets for bootnodes..."
for i in 1 2; do
  KEY_INDEX=$((i - 1))
  KEY_DIR="${NON_VAL_DIR}/${NON_VAL_KEYS[$KEY_INDEX]}"
  NAME="bootnode-${i}"

  PUB_KEY=$(cat "${KEY_DIR}/key.pub" | sed 's/^0x//')
  NODE_ADDRESS="${NON_VAL_KEYS[$KEY_INDEX]}"
  ALL_ADDRESSES+=("${NODE_ADDRESS}")

  ENODE="enode://${PUB_KEY}@${NAME}.${NAMESPACE}.svc.cluster.local:30303"
  ALL_ENODES+=("${ENODE}")
  STATIC_ENODES+=("${ENODE}")

  echo "   Bootnode '${i}' -> Address: ${NODE_ADDRESS}"

  kubectl create secret generic "${NAME}-key" \
    --from-file=key="${KEY_DIR}/key" \
    --from-file=key.pub="${KEY_DIR}/key.pub" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml > "${SECRETS_OUT}/${NAME}-key.yaml"
  kubectl apply -f "${SECRETS_OUT}/${NAME}-key.yaml"
done

# 8. Process RPC nodes (non-validator keys 2 to 7)
echo "8. Creating Secrets for RPC nodes..."
for i in "${!RPC_NAMES[@]}"; do
  ORG="${RPC_NAMES[$i]}"
  KEY_INDEX=$((i + 2))
  KEY_DIR="${NON_VAL_DIR}/${NON_VAL_KEYS[$KEY_INDEX]}"
  NAME="rpc-${ORG}"

  PUB_KEY=$(cat "${KEY_DIR}/key.pub" | sed 's/^0x//')
  NODE_ADDRESS="${NON_VAL_KEYS[$KEY_INDEX]}"
  ALL_ADDRESSES+=("${NODE_ADDRESS}")

  ENODE="enode://${PUB_KEY}@${NAME}.${NAMESPACE}.svc.cluster.local:30303"
  ALL_ENODES+=("${ENODE}")

  echo "   RPC Node '${ORG}' -> Address: ${NODE_ADDRESS}"

  kubectl create secret generic "${NAME}-key" \
    --from-file=key="${KEY_DIR}/key" \
    --from-file=key.pub="${KEY_DIR}/key.pub" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml > "${SECRETS_OUT}/${NAME}-key.yaml"
  kubectl apply -f "${SECRETS_OUT}/${NAME}-key.yaml"
done

# 9. Genesis ConfigMap is created after static-nodes.json generation (step 10 below).
# This ensures both files are bundled in the same ConfigMap.

# 10. Generate static-nodes.json
# NOTE: Besu requires IP addresses in enode URLs, not DNS hostnames.
# Since pod IPs are dynamic in Kubernetes, we use an empty static-nodes.json
# and rely on --bootnodes (with ClusterIP-based enodes) for peer discovery.
echo "10. Generating empty static-nodes.json (discovery via --bootnodes)..."
STATIC_NODES_FILE="${TEMP_DIR}/static-nodes.json"
echo "[]" > "${STATIC_NODES_FILE}"

echo "10b. Creating combined genesis ConfigMap (genesis.json + static-nodes.json)..."
kubectl create configmap besu-private-genesis \
  --from-file=genesis.json="${GENESIS_PATH}" \
  --from-file=static-nodes.json="${STATIC_NODES_FILE}" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml > "${TEMP_DIR}/genesis-configmap.yaml"
kubectl apply -f "${TEMP_DIR}/genesis-configmap.yaml"

# 11. Generate permissions_config.toml
echo "11. Generating permissions_config.toml..."
PERM_FILE="${TEMP_DIR}/permissions_config.toml"
cat <<EOF > "${PERM_FILE}"
# Initial configuration allowlist for nodes and accounts
nodes-allowlist=[
EOF

# Add all enodes to nodes-allowlist
FIRST=true
for ENODE_URL in "${ALL_ENODES[@]}"; do
  if [ "$FIRST" = true ]; then
    echo "  \"${ENODE_URL}\"" >> "${PERM_FILE}"
    FIRST=false
  else
    echo "  ,\"${ENODE_URL}\"" >> "${PERM_FILE}"
  fi
done
echo "]" >> "${PERM_FILE}"

echo "accounts-allowlist=[" >> "${PERM_FILE}"
FIRST=true
for ADDR in "${ALL_ADDRESSES[@]}"; do
  if [ "$FIRST" = true ]; then
    echo "  \"${ADDR}\"" >> "${PERM_FILE}"
    FIRST=false
  else
    echo "  ,\"${ADDR}\"" >> "${PERM_FILE}"
  fi
done
echo "]" >> "${PERM_FILE}"

kubectl create configmap besu-private-permissions \
  --from-file=permissions_config.toml="${PERM_FILE}" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml > "${TEMP_DIR}/permissions-configmap.yaml"
kubectl apply -f "${TEMP_DIR}/permissions-configmap.yaml"

# Copy files to workspace for deployment references (configmap folder)
cp "${GENESIS_PATH}" "${SCRIPT_DIR}/../3.configmap/genesis.json"
cp "${STATIC_NODES_FILE}" "${SCRIPT_DIR}/../3.configmap/static-nodes.json"
cp "${PERM_FILE}" "${SCRIPT_DIR}/../3.configmap/permissions_config.toml"

echo ""
echo "✅ Keys and ConfigMaps successfully extracted and applied to cluster!"
