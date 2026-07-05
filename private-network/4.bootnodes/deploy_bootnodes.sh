#!/bin/bash
# ========================
# Deploy Private Bootnodes
#
# Deploys the designated bootnodes inside the private namespace
# to enable peer discovery among nodes.
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.env"

NAMESPACE="${PRIVATE_NAMESPACE}"
BOOTNODE_COUNT="${PRIVATE_BOOTNODE_COUNT:-2}"

echo "Deploying ${BOOTNODE_COUNT} private bootnodes..."

for i in $(seq 1 "${BOOTNODE_COUNT}"); do
  NAME="bootnode-${i}"
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
            - --rpc-http-enabled=false
            - --permissions-nodes-contract-enabled=true
            - --permissions-nodes-contract-address=${NODE_INGRESS_ADDRESS}
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
          resources:
            requests:
              cpu: "0.5"
              memory: "1Gi"
            limits:
              cpu: "1"
              memory: "2Gi"
          ports:
            - name: p2p-tcp
              containerPort: 30303
              protocol: TCP
            - name: p2p-udp
              containerPort: 30303
              protocol: UDP
            - name: metrics
              containerPort: 9545
              protocol: TCP
          # Readiness/Liveness Probes on Metrics Port (HTTP RPC is disabled)
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
    - name: p2p-tcp
      port: 30303
      targetPort: 30303
      protocol: TCP
    - name: p2p-udp
      port: 30303
      targetPort: 30303
      protocol: UDP
    - name: metrics
      port: 9545
      targetPort: 9545
      protocol: TCP
EOF
done

echo "✅ Bootnodes applied successfully!"
