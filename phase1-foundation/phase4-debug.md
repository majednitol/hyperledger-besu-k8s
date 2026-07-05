# Phase 4 Debugging Playbook

> Diagnostic guides and resolutions for issues encountered during smart contract compiling, Hardhat tests, and deployments in Phase 4.

---

## 1. Hardhat Compilation Errors
* **Symptom**: `npx hardhat compile` fails with compilation errors, missing dependencies, or compiler mismatches.
* **Diagnostics**: Read the detailed compiler stack trace.
* **Common Root Causes**:
  - **Missing OpenZeppelin contracts**: Contracts use OpenZeppelin files (e.g. `@openzeppelin/contracts/...`) but the library wasn't installed.
  - **Solidity Version Mismatch**: Hardhat uses a different Solidity compiler version than the one specified in the contract (`pragma solidity ^0.8.20;`).
  - **Fix**: Run `npm install` inside the `8.contracts/` folder to restore dependencies, and verify Solidity version `0.8.20` is configured in `hardhat.config.js`.

---

## 2. Unit Tests Fail inside Hardhat
* **Symptom**: `npx hardhat test` runs but fails assertions in `PrefixRegistry.test.js` or `Permissioning.test.js`.
* **Diagnostics**: Review the specific test output and assertion message.
* **Common Root Causes**:
  - **Cooldown Period Enforce**: Submitting records sequentially from the same owner without disabling the cooldown period will cause the second transaction to revert. Ensure `await registry.setCooldownPeriod(0)` is called in the `beforeEach` setup of tests.
  - **Signers Mismatch**: Tests sending transactions from accounts that don't match the required modifier roles (e.g., non-validator calling `setStatus` on `PrefixRegistry`).

---

## 3. Ingress `eth_getCode` returns `0x`
* **Symptom**: `phase4-verify.sh` warning: Ingress bytecode not found at pre-allocated address `0x...9999` or `0x...8888`.
* **Diagnostics**:
  ```bash
  curl -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_getCode","params":["0x0000000000000000000000000000000000009999", "latest"],"id":1}' \
    http://rpc-rono.besu-private.svc.cluster.local:8545
  ```
* **Common Root Causes**:
  - **Genesis Allocation Missing**: The genesis file applied during Phase 2 did not allocate the bytecode of `NodeIngress` and `AccountIngress` directly into the blockchain state.
  - **Fix**: If you need onchain permissioning enforced at boot, make sure the compiled bytecode of the ingress contracts is embedded inside `qbftConfigFile.json` under the pre-allocated addresses *before* generating and bootstrapping the chain. Alternatively, deploy them dynamically using Nick's keyless deployment transactions.

---

## 4. Deploy Script Fails with Out Of Gas (OOG)
* **Symptom**: `deploy.js` fails with `Gas limit exceeded` or `Out of Gas` transaction reverts.
* **Fix**: The default block gas limit in the genesis configuration is `0x1C9C380` (30M gas). Verify that the `gas` property in `hardhat.config.js` for the `besuPrivate` network is set to a value below 30M (e.g. `15000000` / 15M gas) so transactions fit within blocks.

---

## 5. Deployment Script Fails "Connection Refused"
* **Symptom**: `hardhat run deploy/deploy.js --network localhost` fails to connect to the JSON-RPC node.
* **Fix**: Establish a port-forward tunnel from your local machine to the running `rpc-rono` pod in the cluster:
  ```bash
  kubectl port-forward svc/rpc-rono 8545:8545 -n besu-private
  ```
  Then run the deployment command again in a separate terminal.
