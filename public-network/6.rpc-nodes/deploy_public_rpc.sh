#!/bin/bash
# ========================
# Deploy Public Network RPC Nodes & Autoscaling
# Deploys public-rpc Deployment (3 replicas) fronted by public-rpc Service,
# and configures HorizontalPodAutoscaler (HPA) targeting 65% CPU.
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.env"

NAMESPACE="${PUBLIC_NAMESPACE}"

echo "Deploying public-rpc Service in ${NAMESPACE}..."
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: Service
metadata:
  name: public-rpc
  labels:
    app: public-rpc
    network: public
spec:
  type: ClusterIP
  selector:
    app: public-rpc
  ports:
    - name: jsonrpc
      port: 8545
      targetPort: 8545
      protocol: TCP
EOF

echo "Deploying public-rpc Deployment..."
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: public-rpc
  labels:
    app: public-rpc
    network: public
spec:
  replicas: 3
  selector:
    matchLabels:
      app: public-rpc
  template:
    metadata:
      labels:
        app: public-rpc
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
            - --bootnodes=${PUBLIC_BOOTNODE_ENODE}
            - --rpc-http-enabled=true
            - --rpc-http-host=0.0.0.0
            - --rpc-http-port=8545
            - --rpc-http-api=ETH,NET,QBFT,WEB3
            - --rpc-http-cors-origins=*
            - --host-allowlist=*
            - --nat-method=NONE
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
          livenessProbe:
            httpGet:
              path: /liveness
              port: 8545
            initialDelaySeconds: 60
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /readiness
              port: 8545
            initialDelaySeconds: 30
            periodSeconds: 15
          volumeMounts:
            - name: data
              mountPath: /data
            - name: genesis
              mountPath: /config
      volumes:
        - name: data
          emptyDir: {}
        - name: genesis
          configMap:
            name: besu-public-genesis
EOF

echo "Deploying public-rpc-hpa Autoscaler..."
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: public-rpc-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: public-rpc
  minReplicas: 3
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 65
EOF
