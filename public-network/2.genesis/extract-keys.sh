#!/bin/bash
# ========================
# Public Network Key & Configuration Extractor
#
# Extracts genesis files and keys from public-genesis-output-pvc,
# creates Kubernetes Secrets for validator and bootnode keys,
# and generates the ConfigMaps (genesis.json, static-nodes.json).
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.env"

TEMP_DIR="/tmp/besu-public-temp"
NAMESPACE="${PUBLIC_NAMESPACE}"

echo "1. Checking if the generate-public-genesis Job has completed..."
STATUS=$(kubectl get job generate-public-genesis -n "${NAMESPACE}" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
if [ "${STATUS}" != "1" ]; then
  echo "  Job 'generate-public-genesis' has not succeeded yet (status: ${STATUS})."
  echo "  Please apply generate-genesis-job.yaml and wait for it to complete."
  exit 1
fi

echo "2. Spinning up helper pod to extract data from PVC..."
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: Pod
metadata:
  name: public-genesis-extractor
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
        claimName: public-genesis-output-pvc
  restartPolicy: Never
EOF

echo "   Waiting for helper pod to be ready..."
kubectl wait --for=condition=Ready pod/public-genesis-extractor -n "${NAMESPACE}" --timeout=60s

echo "3. Copying generated configuration locally..."
rm -rf "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}"
kubectl cp -n "${NAMESPACE}" public-genesis-extractor:/out "${TEMP_DIR}"

echo "4. Tearing down helper pod..."
kubectl delete pod public-genesis-extractor -n "${NAMESPACE}" --wait=false

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
if [ "${#VAL_KEYS[@]}" -ne 5 ]; then
  echo "ERROR: Expected 5 validator keys, found ${#VAL_KEYS[@]}"
  exit 1
fi
if [ "${#NON_VAL_KEYS[@]}" -ne 2 ]; then
  echo "ERROR: Expected 2 bootnode keys, found ${#NON_VAL_KEYS[@]}"
  exit 1
fi

# Create output folder for secrets configuration
SECRETS_OUT="${TEMP_DIR}/secrets-manifests"
mkdir -p "${SECRETS_OUT}"

# 6. Process validator keys (public-validator-1 to public-validator-5)
echo "6. Creating Secrets for validators..."
STATIC_ENODES=()

for i in $(seq 1 5); do
  KEY_INDEX=$((i - 1))
  KEY_DIR="${VAL_DIR}/${VAL_KEYS[$KEY_INDEX]}"
  NAME="public-validator-${i}"

  PUB_KEY=$(cat "${KEY_DIR}/key.pub" | sed 's/^0x//')
  NODE_ADDRESS="${VAL_KEYS[$KEY_INDEX]}"
  
  # Format enode URL for static nodes
  ENODE="enode://${PUB_KEY}@${NAME}-0.${NAME}.${NAMESPACE}.svc.cluster.local:30303"
  STATIC_ENODES+=("${ENODE}")

  echo "   Validator '${i}' -> Address: ${NODE_ADDRESS}"

  # Create K8s Secret manifest
  kubectl create secret generic "${NAME}-key" \
    --from-file=key="${KEY_DIR}/key" \
    --from-file=key.pub="${KEY_DIR}/key.pub" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml > "${SECRETS_OUT}/${NAME}-key.yaml"
  kubectl apply -f "${SECRETS_OUT}/${NAME}-key.yaml"
done

# 7. Process bootnodes (public-bootnode-1 to public-bootnode-2)
echo "7. Creating Secrets for bootnodes..."
for i in $(seq 1 2); do
  KEY_INDEX=$((i - 1))
  KEY_DIR="${NON_VAL_DIR}/${NON_VAL_KEYS[$KEY_INDEX]}"
  NAME="public-bootnode-${i}"

  PUB_KEY=$(cat "${KEY_DIR}/key.pub" | sed 's/^0x//')
  NODE_ADDRESS="${NON_VAL_KEYS[$KEY_INDEX]}"

  ENODE="enode://${PUB_KEY}@${NAME}.${NAMESPACE}.svc.cluster.local:30303"
  STATIC_ENODES+=("${ENODE}")

  echo "   Bootnode '${i}' -> Address: ${NODE_ADDRESS}"

  kubectl create secret generic "${NAME}-key" \
    --from-file=key="${KEY_DIR}/key" \
    --from-file=key.pub="${KEY_DIR}/key.pub" \
    --namespace="${NAMESPACE}" \
    --dry-run=client -o yaml > "${SECRETS_OUT}/${NAME}-key.yaml"
  kubectl apply -f "${SECRETS_OUT}/${NAME}-key.yaml"
done

# 8. Create genesis ConfigMap
echo "8. Creating genesis ConfigMap..."
# Note: static-nodes.json is generated below but we need it in the same configmap.
# We create the configmap after generating static-nodes.json (see step 9 below).
# Placeholder - the actual configmap creation happens after static-nodes generation.

# 9. Generate static-nodes.json
echo "9. Generating static-nodes.json..."
STATIC_NODES_FILE="${TEMP_DIR}/static-nodes.json"
echo "[" > "${STATIC_NODES_FILE}"
FIRST=true
for ENODE_URL in "${STATIC_ENODES[@]}"; do
  if [ "$FIRST" = true ]; then
    echo "  \"${ENODE_URL}\"" >> "${STATIC_NODES_FILE}"
    FIRST=false
  else
    echo "  ,\"${ENODE_URL}\"" >> "${STATIC_NODES_FILE}"
  fi
done
echo "]" >> "${STATIC_NODES_FILE}"

kubectl create configmap besu-public-genesis \
  --from-file=genesis.json="${GENESIS_PATH}" \
  --from-file=static-nodes.json="${STATIC_NODES_FILE}" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml > "${TEMP_DIR}/genesis-configmap.yaml"
kubectl apply -f "${TEMP_DIR}/genesis-configmap.yaml"

# Copy files to workspace for references
cp "${GENESIS_PATH}" "${SCRIPT_DIR}/../3.configmap/genesis.json"
cp "${STATIC_NODES_FILE}" "${SCRIPT_DIR}/../3.configmap/static-nodes.json"

echo ""
echo "✅ Public Keys and ConfigMaps successfully extracted and applied to cluster!"
