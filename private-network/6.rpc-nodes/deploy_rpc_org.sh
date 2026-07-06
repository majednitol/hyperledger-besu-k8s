#!/bin/bash
# ========================
# Deploy Private RPC Nodes
#
# Deploys the 6 RPC nodes (one per RIR/coordinator org) in the private namespace,
# enabling the HTTP JSON-RPC endpoint for application interaction.
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.env"

NAMESPACE="${PRIVATE_NAMESPACE}"
RPC_ORGS=("afrinic" "apnic" "rono")

echo "Deploying ${#RPC_ORGS[@]} private RPC nodes..."

# Resolve bootnode enode URLs using ClusterIP addresses (Besu requires IP, not DNS)
BOOTNODE_ENODES=""
for bi in $(seq 1 "${PRIVATE_BOOTNODE_COUNT:-2}"); do
  BN_IP=$(kubectl get svc "bootnode-${bi}" -n "${NAMESPACE}" -o jsonpath='{.spec.clusterIP}')
  BN_PUBKEY=$(kubectl get secret "bootnode-${bi}-key" -n "${NAMESPACE}" -o jsonpath='{.data.key\.pub}' | base64 -d | sed 's/^0x//')
  if [ -n "${BOOTNODE_ENODES}" ]; then
    BOOTNODE_ENODES="${BOOTNODE_ENODES},"
  fi
  BOOTNODE_ENODES="${BOOTNODE_ENODES}enode://${BN_PUBKEY}@${BN_IP}:30303"
done
echo "  Resolved bootnode enodes: ${BOOTNODE_ENODES}"

for ORG in "${RPC_ORGS[@]}"; do
  NAME="rpc-${ORG}"
  SA_NAME="${NAME}-sa"

  echo "1. Creating ServiceAccount for ${NAME}..."
  kubectl create sa "${SA_NAME}" -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  echo "2. Applying Deployment & Service for ${NAME}..."
  cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}
  labels:
    app: ${NAME}
    network: private
    role: rpc
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${NAME}
  template:
    metadata:
      labels:
        app: ${NAME}
        network: private
        role: rpc
    spec:
      serviceAccountName: ${SA_NAME}
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: besu
          image: ${BESU_IMAGE}
          command:
            - besu
          args:
            - --data-path=/data
            - --genesis-file=/config/genesis.json
            - --node-private-key-file=/keys/key
            - --p2p-port=${PRIVATE_P2P_PORT}
            - --rpc-http-enabled=true
            - --rpc-http-host=0.0.0.0
            - --rpc-http-port=8545
            - --rpc-http-api=ETH,NET,QBFT,WEB3
            - --min-gas-price=0
            - --rpc-http-cors-origins=*
            - --host-allowlist=*
            - --bootnodes=${BOOTNODE_ENODES}
            - --nat-method=NONE
            - --metrics-enabled=true
            - --metrics-port=9545
            - --metrics-host=0.0.0.0
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: false
            seccompProfile:
              type: RuntimeDefault
          env:
            - name: BESU_OPTS
              value: "-Xmx256m -Xms128m -XX:+UseG1GC -XX:MaxDirectMemorySize=256m"
          resources:
            requests:
              cpu: "${RPC_CPU_REQUEST}"
              memory: "${RPC_MEM_REQUEST}"
            limits:
              cpu: "${RPC_CPU_LIMIT}"
              memory: "${RPC_MEM_LIMIT}"
          ports:
            - name: rpc-http
              containerPort: 8545
              protocol: TCP
            - name: p2p-tcp
              containerPort: 30303
              protocol: TCP
            - name: p2p-udp
              containerPort: 30303
              protocol: UDP
            - name: metrics
              containerPort: 9545
              protocol: TCP
          startupProbe:
            httpGet:
              path: /liveness
              port: 8545
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 30
          livenessProbe:
            httpGet:
              path: /liveness
              port: 8545
            initialDelaySeconds: 15
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /readiness
              port: 8545
            initialDelaySeconds: 15
            periodSeconds: 15
          volumeMounts:
            - name: data
              mountPath: /data
            - name: genesis
              mountPath: /config
            - name: key
              mountPath: /keys
              readOnly: true
            - name: tls
              mountPath: /tls
              readOnly: true
            - name: tls-password
              mountPath: /tls-password
              readOnly: true
            - name: known-clients
              mountPath: /known-clients
              readOnly: true
      volumes:
        - name: data
          emptyDir: {}
        - name: genesis
          configMap:
            name: besu-private-genesis
        - name: key
          secret:
            secretName: ${NAME}-key
        - name: tls
          secret:
            secretName: ${NAME}-tls
        - name: tls-password
          secret:
            secretName: besu-keystore-password
        - name: known-clients
          configMap:
            name: besu-private-known-clients
---
apiVersion: v1
kind: Service
metadata:
  name: ${NAME}
spec:
  type: ClusterIP
  selector:
    app: ${NAME}
  ports:
    - name: json-rpc
      port: 8545
      targetPort: 8545
      protocol: TCP
    - name: metrics
      port: 9545
      targetPort: 9545
      protocol: TCP
EOF
done

echo "✅ RPC nodes applied successfully!"
