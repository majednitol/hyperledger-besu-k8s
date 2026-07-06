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
| **Blockscout UI** | **Mismatched** | `blockscout-frontend` (4001) | Browser verification (API endpoint errors) |

---

## 2. Deep Dive: Known Issues & Technical Constraints

### 🔴 Issue 1: Blockscout Frontend Client-Side API Resolution
* **Type**: Open Issue (Configuration Mismatch)
* **Symptom**: Navigating to `http://localhost:4001` renders the Blockscout template, but displays **"undefined explorer"** and **"No data. Please reload the page."**.
* **Root Cause**: Next.js bakes environment variables starting with `NEXT_PUBLIC_` into the static JavaScript bundle at compile time. The pre-built image `ghcr.io/blockscout/frontend:latest` was deployed with:
  * `NEXT_PUBLIC_API_HOST=blockscout.besu-app.svc.cluster.local`
  When accessed by a client web browser outside the Kubernetes cluster, the browser cannot resolve `blockscout.besu-app.svc.cluster.local`, causing all client-side network requests to fail.
* **Workaround**: We have deployed static HTML/Ethers explorers served directly by the API Gateway. These bypass the Next.js bundle and fetch blocks locally:
  * **Public Explorer**: `http://localhost:3000/explorer-public/` (Input `http://localhost:28545` as the RPC endpoint)
  * **Private Explorer**: `http://localhost:3000/explorer-private/` (Input `http://localhost:18545` as the RPC endpoint)
* **Action Item for Next Agent**: Either rebuild the `blockscout/frontend` image passing `NEXT_PUBLIC_API_HOST=localhost:4000` at build time, or configure Nginx Ingress in Minikube to route `/api` requests on the host domain.

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
