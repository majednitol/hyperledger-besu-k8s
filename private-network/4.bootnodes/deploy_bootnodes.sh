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
            - --rpc-http-enabled=false
            - --nat-method=NONE
            - --min-gas-price=0
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
          env:
            - name: BESU_OPTS
              value: "-Xmx256m -Xms128m -XX:+UseG1GC -XX:MaxDirectMemorySize=256m"
          resources:
            requests:
              cpu: "${BOOTNODE_CPU_REQUEST}"
              memory: "${BOOTNODE_MEM_REQUEST}"
            limits:
              cpu: "${BOOTNODE_CPU_LIMIT}"
              memory: "${BOOTNODE_MEM_LIMIT}"
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
          startupProbe:
            tcpSocket:
              port: 9545
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 30
          livenessProbe:
            tcpSocket:
              port: 9545
            initialDelaySeconds: 15
            periodSeconds: 30
          readinessProbe:
            tcpSocket:
              port: 9545
            initialDelaySeconds: 15
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
