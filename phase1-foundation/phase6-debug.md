# Phase 6 Debugging Playbook

> Diagnostic guides and resolutions for issues encountered during public node scheduling, P2P discovery, and NetworkPolicy isolation in Phase 6.

---

## 1. Validators stuck in `Pending` state
* **Symptom**: `kubectl get pods -n besu-public` shows validator pods remain in `Pending` state.
* **Diagnostics**:
  ```bash
  kubectl describe pod public-validator-1 -n besu-public
  ```
* **Common Root Causes**:
  - **Resource Exhaustion**: Validators request 2 CPU and 4Gi memory. If the cluster nodes have insufficient free capacity, the pods cannot schedule.
  - **Zone Spread Constraints**: The pod anti-affinity topology key (`topology.kubernetes.io/zone`) forces scheduler to place validators on separate zone nodes. If you have fewer zones than validators (e.g. only 3 zones for 5 validators), the scheduler will refuse to schedule the remaining validators on the same zones unless configured as `preferredDuringScheduling` rather than `requiredDuringScheduling`.
  - **Fix**: The manifest is configured as `preferredDuringSchedulingIgnoredDuringExecution` (Soft constraint) to prevent this lockup. If resources are low, lower the CPU request/limits in `deploy_public_validators.sh` to fit your cluster nodes capacity.

---

## 2. Bootnodes LoadBalancer status remains `Pending`
* **Symptom**: `kubectl get svc -n besu-public` shows external IP is `<pending>` forever.
* **Diagnostics**:
  ```bash
  kubectl describe svc public-bootnode-1 -n besu-public
  ```
* **Common Root Causes**:
  - **Cloud quota exceeded**: Your cloud provider subscription has reached the maximum number of network load balancers permitted.
  - **Local Dev Environment**: Running in a local environment (Kind/K3s) without an active load balancer controller (like MetalLB) or Minikube tunnel.
  - **Fix**: Run `minikube tunnel` to resolve pending external IPs locally. In cloud environments, check your quota dashboard or switch the service type to `NodePort`.

---

## 3. Nodes fail to discover peers (height does not progress)
* **Symptom**: `phase6-verify.sh` warning: "Public block height did not progress". Logs show zero peers connected.
* **Diagnostics**:
  ```bash
  kubectl logs -n besu-public -l app=public-rpc -c besu
  ```
* **Common Root Causes**:
  - **Bootnodes config misaligned**: The bootnodes enode URL inside `config.env` (`PUBLIC_BOOTNODE_ENODE`) contains an incorrect public key or host address.
  - **P2P ports blocked**: NetworkPolicies or external firewalls are blocking TCP/UDP traffic on port `30303`.
  - **Fix**: Double check that the enode URL public key matches the public key generated in the `public-bootnode-1-key` secret (`key.pub`). Verify that the P2P ports are open in the NetworkPolicy rules.

---

## 4. `kubectl drain` is blocked by PDB
* **Symptom**: Attempting to drain a node fails with `cannot evict pod ... due to PodDisruptionBudget`.
* **Diagnostics**:
  ```bash
  kubectl get pdb -n besu-public
  ```
* **Common Root Causes**:
  - ** consensus liveness boundary reached**: The public network has 5 validators. QBFT liveness requires 4 online validators ($N=5, F=1$). Therefore, `public-validators-pdb` enforces `maxUnavailable: 1`. If one validator is already down, you cannot evict another validator.
  - **Fix**: Verify all other validator pods are in `Ready` status before attempting to drain. If needed, manually scale the StatefulSet down to 0 replicas temporarily, or delete the PDB during maintenance and re-apply it after completion.

---

## 5. Ingress Controller returns 502 / 504 Gateway Timeout
* **Symptom**: Querying `https://rpc.public.yourdomain.com` returns a 502 Bad Gateway error.
* **Diagnostics**:
  ```bash
  kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
  ```
* **Common Root Causes**:
  - **RPC Nodes not Ready**: The Ingress controller cannot find any active endpoints for service `public-rpc`. This happens if the RPC pods have not passed their readiness probes.
  - **NetworkPolicy blocking Ingress traffic**: The NetworkPolicy does not allow traffic from the ingress namespace to the RPC pods.
  - **Fix**: Check that the RPC pods have passed readiness probes (`kubectl get pods -n besu-public -l app=public-rpc`). Verify that the ingress namespace is permitted in the `allow-intra-public-p2p-and-ingress` NetworkPolicy under the `ingress` source blocks.
