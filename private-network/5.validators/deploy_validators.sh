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
VAL_ORGS=("afrinic" "apnic" "arin" "ripencc" "lacnic" "rono" "rono-2")

echo "Deploying ${#VAL_ORGS[@]} private validators..."

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
            - --permissions-accounts-contract-enabled=true
            - --permissions-accounts-contract-address=${ACCOUNT_INGRESS_ADDRESS}
            - --static-nodes-file=/config/static-nodes.json
            - --metrics-enabled=true
            - --metrics-port=9545
            - --metrics-host=0.0.0.0
            - --nat-method=NONE
            - --tls-keystore-file=/tls/keystore.pfx
            - --tls-keystore-password-file=/tls/keystore-password
            - --tls-known-clients-file=/tls/known-clients.txt
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
        - name: genesis
          configMap:
            name: besu-private-genesis
        - name: key
          secret:
            secretName: ${NAME}-key
        - name: tls
          secret:
            secretName: ${NAME}-tls
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: ${VALIDATOR_DISK}
        # Uncomment below if you require a specific StorageClass (default is used otherwise)
        # storageClassName: gp3
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
