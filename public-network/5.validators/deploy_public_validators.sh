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
            - --static-nodes-file=/config/static-nodes.json
            - --rpc-http-enabled=false
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
          resources:
            requests:
              cpu: "${VALIDATOR_CPU_REQUEST}"
              memory: "${VALIDATOR_MEM_REQUEST}"
            limits:
              cpu: "${VALIDATOR_CPU_LIMIT}"
              memory: "${VALIDATOR_MEM_LIMIT}"
          # Run health checks on metrics port 9545 (HTTP RPC is disabled)
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
      volumes:
        - name: data
          emptyDir: {}
        - name: genesis
          configMap:
            name: besu-public-genesis
        - name: key
          secret:
            secretName: ${NAME}-key
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
