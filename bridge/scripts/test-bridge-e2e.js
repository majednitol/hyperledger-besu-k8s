/**
 * End-to-end bridge test:
 * 1. Connect to both private and public chains
 * 2. Deploy PrefixRegistry on private
 * 3. Deploy RegistryAnchor on public
 * 4. Register prefixes on private
 * 5. Simulate bridge relay: compute Merkle root from private state, submit to public
 * 6. Verify all data on both chains
 *
 * Usage: node scripts/test-bridge-e2e.js
 */
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

// Config
const PRIVATE_RPC = "http://127.0.0.1:18545";
const PUBLIC_RPC  = "http://127.0.0.1:28545";
const DEPLOYER_KEY = "ae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f";

async function loadArtifact(name) {
  const artifactPath = path.join(__dirname, "..", "artifacts", "contracts", `${name}.sol`, `${name}.json`);
  return JSON.parse(fs.readFileSync(artifactPath, "utf8"));
}

async function main() {
  console.log("=" .repeat(60));
  console.log("  BESU DUAL-CHAIN BRIDGE END-TO-END TEST");
  console.log("=".repeat(60));

  // 1. Connect to both networks
  console.log("\n[1/6] Connecting to both networks...");
  const privateProvider = new ethers.JsonRpcProvider(PRIVATE_RPC);
  const publicProvider  = new ethers.JsonRpcProvider(PUBLIC_RPC);

  const privateWallet = new ethers.Wallet(DEPLOYER_KEY, privateProvider);
  const publicWallet  = new ethers.Wallet(DEPLOYER_KEY, publicProvider);

  const privateChain = await privateProvider.getNetwork();
  const publicChain  = await publicProvider.getNetwork();
  console.log(`  ✓ Private chain: ${privateChain.chainId}`);
  console.log(`  ✓ Public chain:  ${publicChain.chainId}`);
  console.log(`  ✓ Deployer: ${privateWallet.address}`);

  const privBal = await privateProvider.getBalance(privateWallet.address);
  const pubBal  = await publicProvider.getBalance(publicWallet.address);
  console.log(`  ✓ Private balance: ${ethers.formatEther(privBal)} ETH`);
  console.log(`  ✓ Public balance:  ${ethers.formatEther(pubBal)} ETH`);

  // 2. Deploy PrefixRegistry on PRIVATE
  console.log("\n[2/6] Deploying PrefixRegistry on PRIVATE chain...");
  const regArtifact = await loadArtifact("PrefixRegistry");
  const RegFactory = new ethers.ContractFactory(regArtifact.abi, regArtifact.bytecode, privateWallet);
  const registry = await RegFactory.deploy();
  await registry.waitForDeployment();
  const regAddr = await registry.getAddress();
  console.log(`  ✓ PrefixRegistry deployed at: ${regAddr}`);

  // 3. Deploy RegistryAnchor on PUBLIC
  console.log("\n[3/6] Deploying RegistryAnchor on PUBLIC chain...");
  const anchorArtifact = await loadArtifact("RegistryAnchor");
  const AnchorFactory = new ethers.ContractFactory(anchorArtifact.abi, anchorArtifact.bytecode, publicWallet);
  const anchor = await AnchorFactory.deploy(publicWallet.address);
  await anchor.waitForDeployment();
  const anchorAddr = await anchor.getAddress();
  console.log(`  ✓ RegistryAnchor deployed at: ${anchorAddr}`);

  // 4. Register test prefixes on PRIVATE
  console.log("\n[4/6] Registering IP prefixes on PRIVATE chain...");
  const testPrefixes = [
    { cidr: "192.168.0.0/16", rir: "APNIC" },
    { cidr: "41.0.0.0/8",     rir: "AFRINIC" },
  ];

  for (const p of testPrefixes) {
    const tx = await registry.registerPrefix(p.cidr, p.rir);
    const receipt = await tx.wait();
    const blockNum = receipt.blockNumber;
    console.log(`  ✓ ${p.cidr} (${p.rir}) → block #${blockNum}, tx: ${tx.hash.slice(0, 18)}...`);
  }

  const total = await registry.totalPrefixes();
  console.log(`  Total prefixes registered: ${total}`);

  // 5. Simulate bridge relay
  console.log("\n[5/6] Simulating bridge relay (private → public)...");
  // Compute a Merkle root from the private state
  const leaves = [];
  for (let i = 0; i < Number(total); i++) {
    const p = await registry.getPrefix(i);
    const leaf = ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["uint256", "string", "string", "address", "bool"],
        [i, p.cidr, p.rir, p.holder, p.active]
      )
    );
    leaves.push(leaf);
  }

  // Simple Merkle root (hash all leaves together)
  let merkleRoot = leaves[0];
  for (let i = 1; i < leaves.length; i++) {
    merkleRoot = ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["bytes32", "bytes32"],
        [merkleRoot, leaves[i]]
      )
    );
  }

  const privateBlock = await privateProvider.getBlockNumber();
  console.log(`  Computed Merkle root: ${merkleRoot.slice(0, 22)}...`);
  console.log(`  Private block number: ${privateBlock}`);

  // Submit anchor to public chain
  const anchorTx = await anchor.submitAnchor(merkleRoot, privateBlock);
  const anchorReceipt = await anchorTx.wait();
  console.log(`  ✓ Anchor submitted on public chain!`);
  console.log(`    Public tx: ${anchorTx.hash}`);
  console.log(`    Public block: ${anchorReceipt.blockNumber}`);

  // 6. Verify data on both chains
  console.log("\n[6/6] Verifying data on both chains...");

  // Verify private chain data
  console.log("  --- Private Chain (PrefixRegistry) ---");
  for (let i = 0; i < Number(total); i++) {
    const p = await registry.getPrefix(i);
    console.log(`  [${i}] ${p.cidr} | ${p.rir} | holder: ${p.holder.slice(0, 12)}... | active: ${p.active}`);
  }

  // Verify public chain data
  console.log("  --- Public Chain (RegistryAnchor) ---");
  const anchorCount = await anchor.totalAnchors();
  console.log(`  Total anchors: ${anchorCount}`);
  const latestAnchor = await anchor.latest();
  console.log(`  Latest anchor:`);
  console.log(`    Merkle Root: ${latestAnchor.merkleRoot.slice(0, 22)}...`);
  console.log(`    Private Block: ${latestAnchor.privateBlockNumber}`);
  console.log(`    Timestamp: ${new Date(Number(latestAnchor.timestamp) * 1000).toISOString()}`);

  // Cross-chain verification
  const rootsMatch = latestAnchor.merkleRoot === merkleRoot;
  console.log(`\n  Cross-chain root match: ${rootsMatch ? "✅ PASS" : "❌ FAIL"}`);

  console.log("\n" + "=".repeat(60));
  if (rootsMatch) {
    console.log("  ✅ ALL TESTS PASSED — Bridge relay verified end-to-end!");
  } else {
    console.log("  ❌ TEST FAILED — Merkle root mismatch");
    process.exit(1);
  }
  console.log("=".repeat(60));

  // Save deployment addresses
  const deploymentInfo = {
    timestamp: new Date().toISOString(),
    private: {
      chainId: Number(privateChain.chainId),
      rpc: PRIVATE_RPC,
      PrefixRegistry: regAddr,
      totalPrefixes: Number(total)
    },
    public: {
      chainId: Number(publicChain.chainId),
      rpc: PUBLIC_RPC,
      RegistryAnchor: anchorAddr,
      totalAnchors: Number(anchorCount)
    },
    bridge: {
      merkleRoot: merkleRoot,
      privateBlockSnapshotted: privateBlock
    }
  };

  const outPath = path.join(__dirname, "..", "deployment.json");
  fs.writeFileSync(outPath, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\nDeployment info saved to: ${outPath}`);
}

main().catch((err) => {
  console.error("❌ E2E test failed:", err.message || err);
  process.exit(1);
});
