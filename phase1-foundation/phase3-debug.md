# Phase 3 Debugging Playbook

> Diagnostic guides and resolutions for issues encountered during private network node deployment and network isolation setup.

---

## 1. Node Peer Count Stays `0` (No Connections)
* **Symptom**: `eth_peerCount` returns `0` on all nodes. Nodes are running but not peering.
* **Diagnostics**:
  ```bash
  kubectl logs validator-afrinic-0 -n besu-private -c besu | grep -iE "tls|handshake|disconnect"
  ```
* **Common Root Causes**:
  - **mTLS Fingerprint Mismatch**: If you regenerate certificates or rotate keys, the SHA-256 fingerprints inside the `besu-private-known-clients` ConfigMap (`known-clients.txt`) might be stale. Besu will immediately drop connections with untrusted certificate fingerprints.
  - **Fix**: Re-run the TLS generation script:
    ```bash
    bash private-network/3.5.tls/generate-tls-certs.sh
    # Restart nodes to reload the ConfigMap
    kubectl rollout restart statefulset -n besu-private
    ```

---

## 2. Pod stuck in `ContainerCreating` or `Pending`
* **Symptom**: Validator pods do not start; status is `ContainerCreating` or `Pending`.
* **Diagnostics**:
  ```bash
  kubectl describe pod validator-afrinic-0 -n besu-private
  ```
* **Common Root Causes**:
  - **PVC Binding Failure**: The `volumeClaimTemplates` requested `100Gi` disk storage under the default storage class. If the cluster cannot dynamically provision 100Gi volumes (or lacks a default StorageClass), it will hang.
  - **Fix**: Verify PVC status:
    ```bash
    kubectl get pvc -n besu-private
    ```
    If pending, update the storage capacity request in `deploy_validators.sh` to a smaller size (e.g. 10Gi) or configure a valid `StorageClass` via `storageClassName` in the template.

---

## 3. Probes Failing / Pod Crashing (`CrashLoopBackOff`)
* **Symptom**: Pods start but are killed repeatedly by Kubernetes because liveness/readiness probes fail.
* **Diagnostics**:
  ```bash
  kubectl describe pod validator-afrinic-0 -n besu-private
  kubectl logs validator-afrinic-0 -n besu-private -c besu --tail=50
  ```
* **Common Root Causes**:
  - **Probe Port Mismatch**: Since validators run with `--rpc-http-enabled=false` to minimize attack surface, port `8545` is closed. If probes are directed to `8545`, they will fail. Probes must be directed to metrics port `9545`, which hosts the `/liveness` and `/readiness` checks.
  - **Delay Too Short**: Besu takes some time to bootstrap the database and load keys. If the probes start too early, they will time out. The deployment configurations use `initialDelaySeconds: 60` for liveness and `30` for readiness.

---

## 4. Block Height Not Increasing (Consensus Halt)
* **Symptom**: Nodes connect and peer count > 0, but `eth_blockNumber` stays at `0` or does not increase over time.
* **Diagnostics**:
  ```bash
  kubectl logs validator-afrinic-0 -n besu-private -c besu | grep -iE "round|validator|block"
  ```
* **Common Root Causes**:
  - **Loss of Quorum**: QBFT requires a supermajority of validators to seal blocks. For $N=7$ validators, the quorum is $F = \lfloor (7-1)/3 \rfloor = 2$ faults tolerated, meaning at least $7 - 2 = 5$ validators must be online, peering, and healthy. If 3 or more validators are offline, block production halts.
  - **Fix**: Ensure at least 5 validator StatefulSets are running and connected. Verify peer count on validators:
    ```bash
    kubectl exec -it validator-afrinic-0 -n besu-private -c besu -- \
      curl -s -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' http://localhost:9545
    ```

---

## 5. DNS Resolution Fails inside Node Containers
* **Symptom**: Node logs show errors resolving other nodes' hostnames.
* **Diagnostics**:
  ```bash
  kubectl exec -it validator-afrinic-0 -n besu-private -c besu -- nslookup kubernetes.default
  ```
* **Common Root Causes**:
  - **NetworkPolicy Blocking DNS**: The `netpol-private.yaml` policy restricts Egress. If the CNI controller enforces strict selectors, it will drop DNS requests unless explicitly allowed.
  - **Fix**: Verify your CoreDNS labels. The policy allows egress to namespace with `kubernetes.io/metadata.name: kube-system` and pod with `k8s-app: kube-dns`. If your cluster uses a different label or namespace for DNS, update the NetworkPolicy manifest accordingly.

---

## 6. TLS Handshake Rejected (Invalid Certificates)
* **Symptom**: Logs show `TLS handshake failed` or `SSLHandshakeException`.
* **Diagnostics**:
  ```bash
  kubectl describe certificate validator-afrinic-tls -n besu-private
  ```
* **Common Root Causes**:
  - **Time Drift**: cert-manager certificates are issued with precise start and end times. If a Kubernetes worker node's clock drifts relative to the control plane, certificates may appear expired or not yet valid to that node.
  - **Fix**: Check time synchronization on all Kubernetes nodes:
    ```bash
    ssh <node-ip> date
    ```
    Ensure NTP daemon (e.g. chrony) is running and active on all hosts.
