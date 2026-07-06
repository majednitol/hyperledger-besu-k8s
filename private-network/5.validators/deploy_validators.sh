#!/bin/bash
# ========================
# Deploy Private Validators
#
# Deploys the 7 validator nodes (6 RIR/coordinator orgs + 1 secondary coordinator)
# as StatefulSets and sets up a PodDisruptionBudget for high availability.
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.env"

NAMESPACE="${PRIVATE_NAMESPACE}"
VAL_ORGS=("afrinic" "apnic" "rono" "rono-2")

echo "Deploying ${#VAL_ORGS[@]} private validators..."

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

for ORG in "${VAL_ORGS[@]}"; do
  NAME="validator-${ORG}"
  SA_NAME="${NAME}-sa"

  echo "1. Creating ServiceAccount for ${NAME}..."
  kubectl create sa "${SA_NAME}" -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  echo "2. Applying StatefulSet & Headless Service for ${NAME}..."
  cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${NAME}
  labels:
    app: ${NAME}
    network: private
    role: validator
spec:
  serviceName: ${NAME}
  replicas: 1
  selector:
    matchLabels:
      app: ${NAME}
  template:
    metadata:
      labels:
        app: ${NAME}
        network: private
        role: validator
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
            - --bootnodes=${BOOTNODE_ENODES}
            - --min-gas-price=0
            - --metrics-enabled=true
            - --metrics-port=9545
            - --metrics-host=0.0.0.0
            - --nat-method=NONE
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
              cpu: "${VALIDATOR_CPU_REQUEST}"
              memory: "${VALIDATOR_MEM_REQUEST}"
            limits:
              cpu: "${VALIDATOR_CPU_LIMIT}"
              memory: "${VALIDATOR_MEM_LIMIT}"
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
  clusterIP: None
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

# 3. Create PodDisruptionBudget for validators
echo "3. Creating PodDisruptionBudget (maxUnavailable: 1) for validators..."
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: private-validators-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      role: validator
      network: private
EOF

echo "✅ Validators and PDB applied successfully!"
