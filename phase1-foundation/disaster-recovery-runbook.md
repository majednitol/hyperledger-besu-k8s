# Disaster Recovery Runbook

> Operational guides for backing up and restoring private/public Hyperledger Besu networks.

---

## 1. Backup Strategy

### 1.1 Kubernetes VolumeSnapshots (CSI-based)
Configure scheduled, automated volume snapshots for all chain-data volumes in namespaces `besu-private` and `besu-public`.

Apply the `VolumeSnapshotClass` (ensure your cloud provider's CSI driver supports it):
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: besu-snapshot-class
driver: pd.csi.storage.gke.io # Example for GCP; use EBS/EFS for AWS, disk for Azure
deletionPolicy: Delete
```

Create a snapshot manually for a validator PVC:
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: validator-afrinic-snap
  namespace: besu-private
spec:
  volumeSnapshotClassName: besu-snapshot-class
  source:
    persistentVolumeClaimName: data-validator-afrinic-0
```

### 1.2 Off-Cluster Secure Archives
Backup the following configuration elements to a secure, encrypted object storage bucket (e.g. AWS S3, Google Cloud Storage):
1. **Genesis configs**: `genesis.json` for both chains.
2. **Node Private Keys**: Public and private keys (decrypted key files) for all validators and bootnodes.
3. **Contract addresses**: `bridge-addresses` CM contents.

---

## 2. Restore Workflows

### 2.1 Scenario A: Single Validator Node Crash or Volume Corruption
If a validator pod crashes due to state database corruption (e.g., bad blocks or index errors):

1. **Stop the node**:
   ```bash
   kubectl scale statefulset/validator-afrinic --replicas=0 -n besu-private
   ```
2. **Delete the corrupted PVC**:
   ```bash
   kubectl delete pvc data-validator-afrinic-0 -n besu-private
   ```
3. **Recreate the PVC from a VolumeSnapshot**:
   ```yaml
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: data-validator-afrinic-0
     namespace: besu-private
   spec:
     dataSource:
       name: validator-afrinic-snap
       kind: VolumeSnapshot
       apiGroup: snapshot.storage.k8s.io
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 100Gi
   ```
   Apply the PVC manifest.
4. **Restart the node**:
   ```bash
   kubectl scale statefulset/validator-afrinic --replicas=1 -n besu-private
   ```
   The node will boot using the snapshot state and automatically fast-sync the remaining delta blocks from peers.

### 2.2 Scenario B: Consensus Lockup (Stuck Round)
If the QBFT validator set fails to agree on consensus (e.g., due to more than $F$ failures and blocks stop progressing):

1. **Identify offline validators**:
   Check Prometheus dashboard or peer count metrics.
2. **Start offline nodes**:
   Scale up any scaled-down validators.
3. **Emergency Round Reset**:
   If validators are online but stuck, restart all validators sequentially (rolling restart) to force a round change renegotiation:
   ```bash
   kubectl rollout restart statefulset/validator-afrinic -n besu-private
   # Repeat for each validator set
   ```

### 2.3 Scenario C: Complete Network Rebuild from Scratch
If the entire Kubernetes cluster is lost and you must rebuild the blockchain:

1. **Stand up namespaces and RBAC**:
   ```bash
   bash easy-setup/run-private.sh # Installs Phase 1 namespaces and RBAC
   ```
2. **Re-publish Keys Secrets**:
   Deploy the key secrets using your secure off-cluster backups:
   ```bash
   kubectl create secret generic validator-afrinic-key --from-file=key=./backup/afrinic/key --namespace=besu-private
   # Repeat for all 7 validators
   ```
3. **Deploy ConfigMaps**:
   Re-apply the genesis ConfigMaps.
4. **Boot the network**:
   Deploy bootnodes first, then validators and RPC nodes. The nodes will form consensus and start block production at block #0.
