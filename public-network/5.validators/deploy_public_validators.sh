#!/bin/bash
# ========================
# Deploy Public Network Validators
# Deploys 5 validators using StatefulSets, with podAntiAffinity scheduling,
# resource limits, metrics health probes, and a PodDisruptionBudget.
# ========================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.env"

NAMESPACE="${PUBLIC_NAMESPACE}"

# Resolve public bootnode enode URLs using ClusterIP addresses (Besu requires IP, not DNS)
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

for i in $(seq 1 "${PUBLIC_VALIDATOR_COUNT}"); do
  NAME="public-validator-${i}"
  echo "Deploying ServiceAccount and StatefulSet for ${NAME} in ${NAMESPACE}..."

  cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${NAME}-sa
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${NAME}
  labels:
    app: ${NAME}
    network: public
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
        network: public
    spec:
      serviceAccountName: ${NAME}-sa
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      # Anti-affinity spread across nodes in different availability zones
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    network: public
                topologyKey: topology.kubernetes.io/zone
      containers:
        - name: besu
          image: ${BESU_IMAGE}
          args:
            - --data-path=/data
            - --genesis-file=/config/genesis.json
            - --node-private-key-file=/keys/key
            - --p2p-port=${PUBLIC_P2P_PORT}
            - --bootnodes=${BOOTNODE_ENODES}
            - --rpc-http-enabled=false
            - --min-gas-price=0
            - --metrics-enabled=true
            - --metrics-port=9545
            - --metrics-host=0.0.0.0
            - --nat-method=NONE
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
          # Run health checks on metrics port 9545 (HTTP RPC is disabled)
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

# QBFT liveness PodDisruptionBudget
echo "Applying PodDisruptionBudget public-validators-pdb..."
cat <<EOF | kubectl apply -n "${NAMESPACE}" -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: public-validators-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      network: public
EOF
