# Private Network Key Rotation Runbook

> Operational runbook for rotating validator and node keys in the permissioned Hyperledger Besu private network.

---

## Important Safety Rule

> [!CAUTION]
> **Rotate permissioning allowlist entries BEFORE redeploying any validator node.**
> If you rotate the node key and restart the validator node *before* adding the new node key/address to the `NodeRules` (onchain node permissioning) and `AccountRules` (onchain account permissioning) contracts, the node will be permanently rejected by peers. This can cause liveness issues if multiple nodes are rotated incorrectly.

---

## Part 1: TLS Certificate Rotation

cert-manager automatically handles TLS certificate renewal when the `Certificate` resource reaches its `renewBefore` window (15 days before expiration). However, Besu does not dynamically hot-reload the keystore from disk.

To pick up the rotated certificates:
1. cert-manager updates the Secret containing the PKCS#12 keystore.
2. A rolling update of the Besu nodes must be triggered:
   ```bash
   kubectl rollout restart statefulset validator-afrinic -n besu-private
   ```
3. Verify that the node connects and completes TLS handshakes after restart by inspecting log output:
   ```bash
   kubectl logs -l app=validator-afrinic -n besu-private -c besu | grep -i "handshake"
   ```

---

## Part 2: Private Validator Node Key Rotation

If a validator node's private key (`key` / `key.pub`) is compromised or scheduled for routine rotation:

### Step 1: Generate a New Key Pair
Run the generator locally or in a temporary pod to create a new key pair:
```bash
# Example generating a single node config
besu operator generate-blockchain-config --config-file=temp-config.json --to=temp-keys
```

### Step 2: Add the New Key to Permissioning
1. **Onchain node allowlist**: Call `addNode` on the `NodeRules` contract with the new node's enode URL.
2. **Onchain validator pool**: Call `proposeValidatorVote` on QBFT consensus (via JSON-RPC `qbft_proposeValidatorVote` on existing validator nodes) to add the new validator address, and vote it in with a majority of validators.
3. **Local allowlist (temporary)**: Add the new enode and account to `permissions_config.toml` ConfigMap:
   ```bash
   kubectl edit cm besu-private-permissions -n besu-private
   ```

### Step 3: Update K8s Secret
Update the node's key Secret with the new credentials:
```bash
kubectl create secret generic validator-afrinic-key \
  --from-file=key=/path/to/new/key \
  --from-file=key.pub=/path/to/new/key.pub \
  -n besu-private --dry-run=client -o yaml | kubectl apply -f -
```

### Step 4: Perform Rolling Restart
Restart the validator node to mount the new secret:
```bash
kubectl rollout restart statefulset validator-afrinic -n besu-private
```

### Step 5: Remove the Old Key
1. Once the new node is running and validating successfully, propose to remove the old validator address:
   `qbft_proposeValidatorVote(old_address, false)` voted in by majority.
2. Call `removeNode` on the `NodeRules` contract for the old enode URL.
3. Remove the old enode/account from `permissions_config.toml` ConfigMap.
