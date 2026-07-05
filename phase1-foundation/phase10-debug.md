# Phase 10 Debugging Playbook

> Diagnostic guides and resolutions for issues encountered during disaster recovery simulation, load testing, and go-live audits in Phase 10.

---

## 1. Load test reports `ECONNREFUSED` or fails to start
* **Symptom**: Running `node benchmark/load-test.js` terminates immediately with `connect ECONNREFUSED 127.0.0.1:3000`.
* **Diagnostics**: Ensure the API Gateway pod is running and port-forwarded.
* **Fix**: Establish a port-forward tunnel to the API Gateway:
  ```bash
  kubectl port-forward svc/api-gateway 3000:3000 -n besu-app
  ```
  Then run the load test script in another terminal.

---

## 2. Hardening Audit fails "Namespace lacks enforce=restricted label"
* **Symptom**: `phase10-verify.sh` reports namespace PSA label failure.
* **Diagnostics**:
  ```bash
  kubectl get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n"}{end}'
  ```
* **Fix**: Re-apply the mandatory security admission labels:
  ```bash
  kubectl label namespace besu-private pod-security.kubernetes.io/enforce=restricted --overwrite
  kubectl label namespace besu-public pod-security.kubernetes.io/enforce=restricted --overwrite
  kubectl label namespace besu-app pod-security.kubernetes.io/enforce=restricted --overwrite
  ```

---

## 3. VolumeSnapshot creation fails or remains in `ReadyToUse: false`
* **Symptom**: Creating a VolumeSnapshot does not complete, and describes report error.
* **Diagnostics**:
  ```bash
  kubectl describe volumesnapshot validator-afrinic-snap -n besu-private
  ```
* **Common Root Causes**:
  - **Storage driver does not support snapshots**: Check if the CSI driver on your cloud platform supports Kubernetes VolumeSnapshots.
  - **VolumeSnapshotClass missing**: The snapshot references a class name that is not registered.
  - **Fix**: Apply a valid VolumeSnapshotClass and ensure the controller pod for snapshots is running in the kube-system namespace.

---

## 4. On-chain permissioning transaction reverts on RIR addition
* **Symptom**: Trying to add a new organization or node on the private network fails.
* **Diagnostics**: Read the EVM transaction receipt logs for revert reasons.
* **Common Root Causes**:
  - **Caller is not admin**: The key signing the transaction is not registered in the `Admin.sol` contract as a valid administrator.
  - **Fix**: Connect to the Admin contract using the genesis dev account `0xfe3b557e8fb62b89f4916b721be55ceb828dbd73` and add the operator's public address to the admins list first.

---

## 5. Load test fails with `401 Unauthorized` errors
* **Symptom**: The load test reports 100% failed transactions, and stdout prints auth errors.
* **Fix**: The load test obtains its JWT token by calling `/api/login` using a pre-shared secret `dev-rir-secret-key-123456789`. Ensure the `JWT_SECRET` environment variable in the API Gateway deployment matching value matches this key.
