# Governance Runbook

> Operational guides for private/public network membership updates.

---

## 1. Private Network Membership Updates

The private permissioned network enforces node and account allowlists at block 0. To add a new organization (RIR) or node to the network:

### 1.1 Step 1: Fund the Operator
To call allowlist contract write operations, the admin account must execute transactions. Use the pre-funded genesis dev key `0xfe3b557e8fb62b89f4916b721be55ceb828dbd73` for execution.

### 1.2 Step 2: Add Account to Allowlist
To permit a new RIR operator to submit prefix records:
1. Connect to the admin contract console (e.g. using Hardhat or Remix).
2. Call `AccountRules.addAccount(address)` passing the new operator's public address:
   ```bash
   # Execute using Hardhat console or tasks
   npx hardhat run scripts/add-operator.js --network besuPrivate
   ```

### 1.3 Step 3: Add Node to Allowlist
To permit the new organization's node to peer with the existing network:
1. Retrieve the node's enode ID (hex string representing public key).
2. Call `NodeRules.addNode(string)` passing the enode URL:
   ```bash
   # Add new node ID
   npx hardhat run scripts/add-node.js --network besuPrivate
   ```
   Once added, the private bootnodes will immediately allow P2P handshakes from this node.

---

## 2. Public Network Sealer Updates

The public network is permissionless for peering full nodes, but governed by a fixed set of 5 sealers (validators) for block production. Adding a new sealer requires manual consensus coordination:

### 2.1 Step 1: Propose a New Sealer
To propose a new sealer address, a majority of current sealers ($>50\%$) must sign a proposal transaction.

1. **Verify Sealer address**: Retrieve the address of the proposed validator node.
2. **Each validator signs a proposal**:
   From each validator RPC node, submit the `qbft_proposeValidatorVote` RPC call:
   ```bash
   curl -X POST -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"qbft_proposeValidatorVote","params":["0xNewSealerAddress", true],"id":1}' \
     http://rpc-validator-1:8545
   ```
3. **Threshold reached**:
   Once 3 of the 5 validators have submitted the proposal, the new sealer is added to the validator pool at the next block and starts sealing blocks.

### 2.2 Step 2: Remove a Sealer
Similarly, to remove a faulty sealer:
```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"qbft_proposeValidatorVote","params":["0xOldSealerAddress", false],"id":1}' \
  http://rpc-validator-1:8545
```
Once the majority of sealers vote `false`, the validator is evicted from block sealing.
