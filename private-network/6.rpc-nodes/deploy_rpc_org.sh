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
RPC_ORGS=("afrinic" "apnic" "arin" "ripencc" "lacnic" "rono")

echo "Deploying ${#RPC_ORGS[@]} private RPC nodes..."

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
            - --rpc-http-cors-origins=none
            - --host-allowlist=*.besu-private.svc.cluster.local,${NAME}
            - --permissions-nodes-contract-enabled=true
            - --permissions-nodes-contract-address=${NODE_INGRESS_ADDRESS}
            - --permissions-accounts-contract-enabled=true
            - --permissions-accounts-contract-address=${ACCOUNT_INGRESS_ADDRESS}
            - --static-nodes-file=/config/static-nodes.json
            - --nat-method=NONE
            - --tls-keystore-file=/tls/keystore.pfx
            - --tls-keystore-password-file=/tls/keystore-password
            - --tls-known-clients-file=/tls/known-clients.txt
            - --metrics-enabled=true
            - --metrics-port=9545
            - --metrics-host=0.0.0.0
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: false
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
          livenessProbe:
            httpGet:
              path: /liveness
              port: 9545
            initialDelaySeconds: 60
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /readiness
              port: 9545
            initialDelaySeconds: 30
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
