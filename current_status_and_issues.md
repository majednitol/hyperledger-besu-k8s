# Handover Report: Current Status, Tested Components, & Known Issues

This document is compiled for the incoming AI agent or engineer to outline the current state of the Besu network, the testing coverage, and the active technical issues/constraints currently present in the system.

---

## 1. Component Status Summary

| Component | Status | Operational Port / Service | Verification Method |
| :--- | :--- | :--- | :--- |
| **Private Chain** | **Working** | `rpc-doctor` (18545), `rpc-patient` (18545) | Hardhat test suite & E2E script |
| **Public Chain** | **Working** | `public-rpc` (28545) | RegistryAnchor contract deployment |
| **Bridge Daemon** | **Working** | `registry-anchor` (CronJob / Job) | Executed `test-bridge-job` successfully |
| **API Gateway** | **Working** | `api-gateway` (3000) | Express backend log & static UI server |
| **Blockscout UI** | **Working** | `blockscout-frontend` (4001) | Browser verification (Dashboard showing blocks & txs) |

---

## 2. Deep Dive: Known Issues & Technical Constraints

### 🟢 Issue 1: Blockscout Frontend Client-Side API Resolution
* **Type**: **RESOLVED**
* **Symptom**: Navigating to `http://localhost:4001` was showing **"undefined explorer"** and **"No data. Please reload the page."**.
* **Root Cause**: The Next.js frontend uses a startup shell script `./make_envs_script.sh` to compile environment variables (like `NEXT_PUBLIC_API_HOST`) into `/app/public/assets/envs.js` at container boot. Because the Pod was configured to run as UID `10001` instead of `1001` (the owner of the NextJS folders in the container image), it encountered `Permission denied` when trying to create/write the `envs.js` config file and copy the favicon assets. As a result, the client-side environment was unpopulated, causing the API calls to fail.
* **Resolution**: Created `14.blockscout/blockscout-frontend.yaml` defining the frontend deployment, and updated the Pod's `securityContext` to use UID/GID `1001`. This successfully granted permission for the env generation script to execute, resolving all permission errors and loading the block/transaction data correctly.
* **Accessing Explorer**:
  * Ensure backend and frontend port-forwards are running:
    ```bash
    kubectl port-forward svc/blockscout 4000:4000 -n besu-app
    kubectl port-forward svc/blockscout-frontend 4001:3000 -n besu-app
    ```
  * Open `http://localhost:4001` in your browser.

### 🟡 Issue 2: Minikube API Server Saturated (TLS Handshake Timeouts)
* **Type**: Open Constraint (Resource Limits)
* **Symptom**: Commands like `kubectl get pods` occasionally fail with:
  `Unable to connect to the server: net/http: TLS handshake timeout`
* **Root Cause**: Running 9 Besu nodes, a PostgreSQL database, Redis, Blockscout, Blockscout frontend, and the API Gateway simultaneously exceeds local memory and CPU scheduling thresholds.
* **Workaround**: 
  1. Add `--request-timeout=90s` to `kubectl` commands.
  2. Scale down unused resources (e.g., `kubectl scale deployment blockscout blockscout-frontend --replicas=0 -n besu-app`).
  3. Keep the VM resource limit in mind.

### 🟢 Issue 3: Bridge Relayer Account Mismatch
* **Type**: **RESOLVED**
* **Symptom**: Bridge anchoring transactions failed with:
  `transaction execution reverted (reason: MedicalRecordAnchor: Caller is not the authorized relayer)`
* **Root Cause**: The contract `RegistryAnchor.sol` was deployed with the hardcoded deployer address as the authorized relayer in its constructor. However, the `anchor-service` daemon was configured with the static relayer private key corresponding to `0xF6110Fb284A80a52137394082Fc22266AcDd8Dc8`.
* **Resolution**: Updated `bridge/deploy_bridge.sh` to extract the correct relayer public address and pass it directly to the constructor during deployment.

### 🟢 Issue 4: PodSecurity Admission Violations (`restricted:latest`)
* **Type**: **RESOLVED**
* **Symptom**: Creating a bridge Job resulted in `FailedCreate` events:
  `violates PodSecurity "restricted:latest": seccompProfile (pod or container must set securityContext.seccompProfile.type to "RuntimeDefault")`
* **Root Cause**: The `besu-app` namespace enforces the strict Kubernetes PodSecurity restricted profile. The `registry-anchor` CronJob definition did not specify a seccompProfile.
* **Resolution**: Added `seccompProfile: { type: RuntimeDefault }` to the pod securityContext in `bridge/anchor-cronjob.yaml`.

---

## 3. What Has Been Tested & Verified

1. **Private Network Peer Connectivity**: Doctor and Patient validators successfully join the network.
2. **Private Network Transactions**: Tested writing records to `MedicalRecordRegistry` using zero-gas rules and verified they are recorded in blocks.
3. **Hardhat Contract Unit Tests**: All unit tests in `private-network/8.contracts/test/` pass.
4. **State Anchoring bridge daemon**:
   * Reads state from `MedicalRecordRegistry` on the private network.
   * Generates a Merkle Root representing the records.
   * Submits a transaction anchoring the root to the public network `MedicalRecordAnchor` contract.
   * Transaction confirmed in public block.
5. **API Gateway routes**:
   * `/api/records`: Fetches records page.
   * `/api/record`: Authenticated submission endpoint.
   * `/api/anchor`: Fetches latest anchor data from public chain.

---

## 4. What Has NOT Been Tested / Tasked

1. **Scale-up Validation**: Verifying that the network operates correctly when all backup bootnodes and validators are scaled to 100%.
2. **TLS Edge Ingress Routing**: Ingress TLS hosts (`app.yourdomain.com`) are configured with Let's Encrypt production certificates; they are currently untested locally because we don't have public DNS routing to the minikube ingress controller.
3. **Dynamic Org Addition**: The scripts support dynamic generation, but scaling the organizations beyond `doctor` and `patient` has not been tested.
