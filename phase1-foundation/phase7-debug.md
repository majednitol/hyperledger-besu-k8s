# Phase 7 Debugging Playbook

> Diagnostic guides and resolutions for issues encountered during state anchoring, TS compilation, and relayer scheduling in Phase 7.

---

## 1. TS Compiler fails with `Cannot find module 'ethers'`
* **Symptom**: `npx tsc` fails, reporting missing type definitions or unresolved dependencies.
* **Diagnostics**: Inspect `package.json` and node modules inside `bridge/anchor-service/`.
* **Common Root Causes**:
  - **Dependencies not installed**: Ethers.js and types need to be restored prior to compilation.
  - **TypeScript version mismatch**: Hardhat or other local tools might conflict on compilation targets.
  - **Fix**: Run `npm install` inside the `bridge/anchor-service/` folder to download all required packages.

---

## 2. Ingress timeout when relayer fetches private PrefixRegistry
* **Symptom**: Relayer daemon logs show `Connection timeout` or `ECONNREFUSED` when querying the private chain.
* **Diagnostics**:
  ```bash
  kubectl logs -n besu-app -l app=registry-anchor
  ```
* **Common Root Causes**:
  - **NetworkPolicy blocking Egress**: The `relayer-egress-policy` applied in the `besu-app` namespace does not allow traffic to exit the pod on port `8545` to destination namespace `besu-private`.
  - **Incorrect RPC URL**: The environment variable `PRIVATE_RPC_URL` is pointing to an incorrect local address (e.g. `http://localhost:8545` instead of `http://rpc-rono.besu-private.svc.cluster.local:8545`).
  - **Fix**: Verify that the destination namespace matches `besu-private` and the RPC URL is correct. Check that `relayer-egress-policy` matches the selectors.

---

## 3. Merkle Root mismatches between Relayer and Auditor
* **Symptom**: Auditing scripts calculate a different Merkle root than the one submitted on the public contract.
* **Diagnostics**: Check the leaf generation output logs in `anchor-service`.
* **Common Root Causes**:
  - **Sort Order Inconsistency**: JS `Array.prototype.sort()` sorts strings lexicographically but can differ if hex addresses have mixed casing.
  - **Status Mapping mismatch**: The status column values are indexed differently between the contract and the JS script.
  - **Fix**: Ethers.js address strings are converted to lowercase or checksum format before sorting. Ensure keys are sorted using `.sort((a, b) => a.localeCompare(b))` and status mapping checks are consistent.

---

## 4. Relayer Transaction Reverts: "Caller is not the relayer"
* **Symptom**: public RPC returns transaction reverted with: `Caller is not the authorized relayer`.
* **Diagnostics**: Query the contract status using Hardhat:
  ```bash
  npx hardhat run scripts/query-status.js --network besuPublic
  ```
* **Common Root Causes**:
  - **Relayer Key Rotation Mismatch**: The public `RegistryAnchor` was deployed with a constructor parameter pointing to `deployer.address`, but the CronJob is signing transactions with a different key (`RELAYER_KEY`).
  - **Fix**: Ensure that the `RegistryAnchor` constructor is called with the actual relayer address (`0x8f2B1f08465492F0eF197cAA022A4E02597B00C0`), or rotate the relayer account in the contract if rotatable.

---

## 5. CronJob remains `Pending` or fails "ImagePullBackOff"
* **Symptom**: CronJob does not trigger, or the spawned Job pod remains in `ImagePullBackOff` status.
* **Diagnostics**:
  ```bash
  kubectl get pods -n besu-app
  kubectl describe pod <cron-job-pod-name> -n besu-app
  ```
* **Common Root Causes**:
  - **Local image not pushed**: The container image `localhost:5001/anchor-service:latest` is missing in the local repository.
  - **Fix**: Build and push the image before deploying:
    ```bash
    docker build -t localhost:5001/anchor-service:latest -f bridge/anchor-service/Dockerfile .
    docker push localhost:5001/anchor-service:latest
    ```
