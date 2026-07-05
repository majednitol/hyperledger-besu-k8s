#!/bin/bash
# ========================
# Private Network TLS Certificate Generator
#
# Creates cert-manager Certificate resources for all 15 private network nodes,
# waits for cert-manager to issue the certificates, extracts their SHA-256
# fingerprints, and generates the known-clients.txt ConfigMap for mTLS.
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.env"

NAMESPACE="${PRIVATE_NAMESPACE}"
VAL_NAMES=("afrinic" "apnic" "arin" "ripencc" "lacnic" "rono" "rono-2")
RPC_NAMES=("afrinic" "apnic" "arin" "ripencc" "lacnic" "rono")

echo "1. Creating keystore password secret..."
PASSWORD="besusharedkeystorepassword123"
kubectl create secret generic besu-keystore-password \
  --from-literal=password="${PASSWORD}" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Temporary files directory
TEMP_DIR="/tmp/besu-tls-temp"
rm -rf "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}"

echo "2. Applying CA Issuer..."
kubectl apply -f "${SCRIPT_DIR}/ca-issuer.yaml"

# Helper function to generate and apply Certificate manifest
create_cert() {
  local name=$1
  local dns_name=$2
  echo "   Generating Certificate manifest for ${name}..."
  cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${name}-tls
spec:
  secretName: ${name}-tls
  issuerRef:
    name: besu-private-ca-issuer
    kind: Issuer
  commonName: ${dns_name}
  dnsNames:
    - ${dns_name}
    - ${name}
    - ${name}.${NAMESPACE}.svc.cluster.local
  keystores:
    pkcs12:
      create: true
      passwordSecretRef:
        name: besu-keystore-password
        key: password
  duration: 2160h
  renewBefore: 360h
  usages:
    - digital signature
    - key encipherment
    - server auth
    - client auth
EOF
}

echo "3. Creating cert-manager Certificates for validators..."
for ORG in "${VAL_NAMES[@]}"; do
  NAME="validator-${ORG}"
  DNS_NAME="${NAME}-0.${NAME}.${NAMESPACE}.svc.cluster.local"
  create_cert "${NAME}" "${DNS_NAME}"
done

echo "4. Creating cert-manager Certificates for bootnodes..."
for i in 1 2; do
  NAME="bootnode-${i}"
  DNS_NAME="${NAME}.${NAMESPACE}.svc.cluster.local"
  create_cert "${NAME}" "${DNS_NAME}"
done

echo "5. Creating cert-manager Certificates for RPC nodes..."
for ORG in "${RPC_NAMES[@]}"; do
  NAME="rpc-${ORG}"
  DNS_NAME="${NAME}.${NAMESPACE}.svc.cluster.local"
  create_cert "${NAME}" "${DNS_NAME}"
done

echo "6. Waiting for cert-manager to issue all certificates (secrets generation)..."
# We check all 15 secrets to ensure they contain TLS data
ALL_NODES=()
for ORG in "${VAL_NAMES[@]}"; do ALL_NODES+=("validator-${ORG}"); done
for i in 1 2; do ALL_NODES+=("bootnode-${i}"); done
for ORG in "${RPC_NAMES[@]}"; do ALL_NODES+=("rpc-${ORG}"); done

for NODE in "${ALL_NODES[@]}"; do
  echo "   Waiting for certificate secret ${NODE}-tls to be ready..."
  # Wait for secret to exist and have non-empty tls.crt
  until kubectl get secret "${NODE}-tls" -n "${NAMESPACE}" -o jsonpath='{.data.tls\.crt}' >/dev/null 2>&1; do
    sleep 2
  done
done

echo "7. Generating known-clients.txt with SHA-256 fingerprints..."
KNOWN_CLIENTS_FILE="${TEMP_DIR}/known-clients.txt"
touch "${KNOWN_CLIENTS_FILE}"

for NODE in "${ALL_NODES[@]}"; do
  # Extract cert and write to temp file
  kubectl get secret "${NODE}-tls" -n "${NAMESPACE}" -o jsonpath='{.data.tls\.crt}' | openssl base64 -d -A > "${TEMP_DIR}/${NODE}.crt"
  
  # Calculate fingerprint
  # openssl output format: (stdin)= 12:34:56... -> strip prefix and colons, lowercase
  FINGERPRINT=$(openssl x509 -in "${TEMP_DIR}/${NODE}.crt" -outform DER | openssl dgst -sha256 | cut -d' ' -f2 | tr 'A-Z' 'a-z')
  
  # Besu known-clients.txt syntax: <common_name_or_domain> <fingerprint>
  # Retrieve the exact commonName from Certificate resource
  CN=$(kubectl get certificate "${NODE}-tls" -n "${NAMESPACE}" -o jsonpath='{.spec.commonName}')
  
  echo "${CN} ${FINGERPRINT}" >> "${KNOWN_CLIENTS_FILE}"
  echo "   Fingerprint for ${NODE} (${CN}) -> ${FINGERPRINT}"
done

echo "8. Creating known-clients ConfigMap..."
kubectl create configmap besu-private-known-clients \
  --from-file=known-clients.txt="${KNOWN_CLIENTS_FILE}" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml > "${TEMP_DIR}/known-clients-configmap.yaml"
kubectl apply -f "${TEMP_DIR}/known-clients-configmap.yaml"

# Copy known-clients.txt to configmap folder in workspace
cp "${KNOWN_CLIENTS_FILE}" "${SCRIPT_DIR}/../3.configmap/known-clients.txt"

echo ""
echo "✅ TLS Certificate resources created and known-clients.txt successfully generated!"
