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

# Resolve bootnode enode URLs using ClusterIP addresses (Besu requires IP, not DNS)
BOOTNODE_ENODES=""
for bi in $(seq 1 "${PUBLIC_BOOTNODE_COUNT:-2}"); do
  BN_IP=$(kubectl get svc "public-bootnode-${bi}" -n "${NAMESPACE}" -o jsonpath='{.spec.clusterIP}')
  BN_PUBKEY=$(kubectl get secret "public-bootnode-${bi}-key" -n "${NAMESPACE}" -o jsonpath='{.data.key\.pub}' | base64 -d | sed 's/^0x//')
  if [ -n "${BOOTNODE_ENODES}" ]; then
    BOOTNODE_ENODES="${BOOTNODE_ENODES},"
  fi
  BOOTNODE_ENODES="${BOOTNODE_ENODES}enode://${BN_PUBKEY}@${BN_IP}:30303"
done
echo "  Resolved bootnode enodes: ${BOOTNODE_ENODES}"

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
  replicas: 1
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
            - --bootnodes=${BOOTNODE_ENODES}
            - --rpc-http-enabled=true
            - --rpc-http-host=0.0.0.0
            - --rpc-http-port=8545
            - --rpc-http-api=ETH,NET,QBFT,WEB3
            - --min-gas-price=0
            - --rpc-http-cors-origins=*
            - --host-allowlist=*
            - --nat-method=NONE
            - --logging=DEBUG
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
  minReplicas: 1
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 65
EOF
