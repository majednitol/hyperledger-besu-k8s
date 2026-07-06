# Running the Hyperledger Besu Dual-Network Project on Minikube

This document provides step-by-step instructions to initialize, run, scale, verify, and clean up the entire Hyperledger Besu dual-network cluster (Private & Public consortia) locally on a single machine using Minikube.

---

## 1. Prerequisites & Environment Setup

Start Minikube with the required resources (at least 8GB RAM, 8 CPUs, and 20GB disk):
```bash
minikube start --disk-size=20g --memory=7835 --cpus=8
```

Ensure the local share directory `/Users/majedurrahman/nfs_share` is mounted inside the Minikube VM as `/mnt/data`:
```bash
# Keep this command running in a dedicated terminal pane or run in background
minikube mount /Users/majedurrahman/nfs_share:/mnt/data
```

Verify that namespaces are created:
```bash
kubectl apply -f phase1-foundation/namespaces.yaml
```

Apply RBAC permissions across all namespaces:
```bash
kubectl apply -f phase1-foundation/rbac-private.yaml
kubectl apply -f phase1-foundation/rbac-public.yaml
kubectl apply -f phase1-foundation/rbac-app.yaml
```

---

## 2. Deploying the Entire Project (Orchestrated)

You can run the full deployment pipeline end-to-end using the master orchestrator script:
```bash
# Move to the network directory
cd "/Users/majedurrahman/coding/hyperledger besu /besu-network"

# Run the full orchestrator
bash easy-setup/run.sh
```

---

## 3. Deploying Component-by-Component (Manual Execution)

If you prefer to deploy or restart specific segments of the topology, run the following:

### Step A: Private Network Setup (Phases 2-4)
```bash
# 1. Genesis Generation
kubectl apply -n besu-private -f private-network/2.genesis/generate-genesis-job.yaml
kubectl wait --for=condition=complete job/generate-genesis -n besu-private --timeout=120s

# 2. Extract Keys & ConfigMaps
bash private-network/2.genesis/extract-keys.sh

# 3. Cert-Manager & TLS Keys Setup
bash private-network/3.5.tls/cert-manager-install.sh
bash private-network/3.5.tls/generate-tls-certs.sh

# 4. Bootnodes
bash private-network/4.bootnodes/deploy_bootnodes.sh

# 5. Validators
bash private-network/5.validators/deploy_validators.sh

# 6. RPC Nodes
bash private-network/6.rpc-nodes/deploy_rpc_org.sh
```

### Step B: Public Network Setup (Phases 5-6)
```bash
# 1. Storage & Genesis
kubectl apply -n besu-public -f public-network/1.storage/pvc.yaml
kubectl apply -n besu-public -f public-network/2.genesis/generate-genesis-job.yaml
kubectl wait --for=condition=complete job/generate-public-genesis -n besu-public --timeout=120s

# 2. Extract Keys
bash public-network/2.genesis/extract-keys.sh

# 3. Bootnodes
bash public-network/4.bootnodes/deploy_public_bootnode.sh

# 4. Validators
bash public-network/5.validators/deploy_public_validators.sh

# 5. RPC Nodes
bash public-network/6.rpc-nodes/deploy_public_rpc.sh
```

### Step C: Cross-Network Bridge Relayer (Phase 7)
```bash
# Deploy the Anchor & Registry Bridge Service
bash bridge/deploy_bridge.sh
```

---

## 4. Verification & Status Checks

### Check Cluster Readiness
To see all running pods in the namespaces:
```bash
kubectl get pods -n besu-private
kubectl get pods -n besu-public
```

### Verify Block Production & Consensus (QBFT)
View the logs of a validator in the private network:
```bash
kubectl logs validator-afrinic-0 -n besu-private --tail=50 -f
```
*(Look for `Imported empty block #...` logs)*

View the logs of a validator in the public network:
```bash
kubectl logs public-validator-1-0 -n besu-public --tail=50 -f
```

---

## 5. Local Resource Optimization (For memory limits < 8GB)

Because running 25+ Java nodes simultaneously can deplete Minikube's 8GB RAM and cause OOM-kills, the configuration uses memory-saving limits (`BESU_OPTS="-Xmx256m"`) and the redundant nodes are scaled down:

```bash
# Scale down private RPC replicas to 0 (leaving rpc-afrinic for RPC requests)
kubectl scale deployment/rpc-apnic deployment/rpc-arin deployment/rpc-lacnic deployment/rpc-ripencc deployment/rpc-rono --replicas=0 -n besu-private

# Scale down public RPC replicas to 1
kubectl scale deployment/public-rpc --replicas=1 -n besu-public

# Scale down duplicate public bootnodes
kubectl scale deployment/public-bootnode-2 --replicas=0 -n besu-public
```

---

## 6. Teardown & Clean Up

To wipe all running workloads and start completely fresh:
```bash
# Delete all Private Network deployments/statefulsets
kubectl delete deployments,statefulsets --all -n besu-private

# Delete all Public Network deployments/statefulsets
kubectl delete deployments,statefulsets --all -n besu-public

# Delete all namespace PVCs (persistent data volumes)
kubectl delete pvc --all -n besu-private
kubectl delete pvc --all -n besu-public
```
