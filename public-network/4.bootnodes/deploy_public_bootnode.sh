#!/bin/bash
# ========================
# Deploy Public Network Bootnodes
# Deploys 2 bootnodes with dedicated LoadBalancer Services.
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.env"

NAMESPACE="${PUBLIC_NAMESPACE}"

for i in $(seq 1 "${PUBLIC_BOOTNODE_COUNT}"); do
  NAME="public-bootnode-${i}"
  echo "Deploying ${NAME} in namespace ${NAMESPACE}..."

  cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}
  labels:
    app: ${NAME}
    network: public
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${NAME}
  template:
    metadata:
      labels:
        app: ${NAME}
        network: public
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
        - name: besu
          image: ${BESU_IMAGE}
          args:
            - --data-path=/data
            - --genesis-file=/config/genesis.json
            - --node-private-key-file=/keys/key
            - --p2p-port=${PUBLIC_P2P_PORT}
            - --rpc-http-enabled=false
            - --nat-method=NONE
            - --discovery-enabled=true
            - --min-gas-price=0
            - --metrics-enabled=true
            - --metrics-port=9545
            - --metrics-host=0.0.0.0
            - --sync-min-peers=2
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
          volumeMounts:
            - name: data
              mountPath: /data
            - name: genesis
              mountPath: /config
            - name: key
              mountPath: /keys
              readOnly: true
      volumes:
        - name: data
          emptyDir: {}
        - name: genesis
          configMap:
            name: besu-public-genesis
        - name: key
          secret:
            secretName: ${NAME}-key
---
apiVersion: v1
kind: Service
metadata:
  name: ${NAME}
  labels:
    app: ${NAME}
    network: public
spec:
  type: LoadBalancer
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
