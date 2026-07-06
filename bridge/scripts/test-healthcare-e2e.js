/**
 * Healthcare Dual-Chain End-to-End Test:
 * 1. Connect to private and public RPC endpoints.
 * 2. Deploy MedicalRecordRegistry on PRIVATE network.
 * 3. Deploy MedicalRecordAnchor on PUBLIC network.
 * 4. Register medical records on PRIVATE network.
 * 5. Compute Merkle root of all records and anchor it to the PUBLIC network.
 * 6. Cross-verify state across both chains.
 *
 * Usage: node scripts/test-healthcare-e2e.js
 */
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const PRIVATE_RPC = "http://127.0.0.1:18545";
const PUBLIC_RPC  = "http://127.0.0.1:28545";
const DEPLOYER_KEY = "0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f";

async function loadArtifact(name) {
  const artifactPath = path.join(__dirname, "..", "artifacts", "contracts", `${name}.sol`, `${name}.json`);
  return JSON.parse(fs.readFileSync(artifactPath, "utf8"));
}

async function main() {
  console.log("=" .repeat(60));
  console.log("  HEALTHCARE DUAL-CHAIN BRIDGE END-TO-END TEST");
  console.log("=".repeat(60));

  // 1. Connection
  console.log("\n[1/6] Connecting to networks...");
  const privateProvider = new ethers.JsonRpcProvider(PRIVATE_RPC);
  const publicProvider  = new ethers.JsonRpcProvider(PUBLIC_RPC);

  const privateWallet = new ethers.Wallet(DEPLOYER_KEY, privateProvider);
  const publicWallet  = new ethers.Wallet(DEPLOYER_KEY, publicProvider);

  const privateChain = await privateProvider.getNetwork();
  const publicChain  = await publicProvider.getNetwork();
  console.log(`  ✓ Private Chain ID: ${privateChain.chainId}`);
  console.log(`  ✓ Public Chain ID:  ${publicChain.chainId}`);

  // 2. Deploy Private Registry
  console.log("\n[2/6] Deploying MedicalRecordRegistry to PRIVATE network...");
  const regArtifact = await loadArtifact("MedicalRecordRegistry");
  const RegFactory = new ethers.ContractFactory(regArtifact.abi, regArtifact.bytecode, privateWallet);
  const registry = await RegFactory.deploy();
  await registry.waitForDeployment();
  const regAddr = await registry.getAddress();
  console.log(`  ✓ MedicalRecordRegistry deployed at: ${regAddr}`);

  // 3. Deploy Public Anchor
  console.log("\n[3/6] Deploying MedicalRecordAnchor to PUBLIC network...");
  const anchorArtifact = await loadArtifact("MedicalRecordAnchor");
  const AnchorFactory = new ethers.ContractFactory(anchorArtifact.abi, anchorArtifact.bytecode, publicWallet);
  const anchor = await AnchorFactory.deploy(publicWallet.address);
  await anchor.waitForDeployment();
  const anchorAddr = await anchor.getAddress();
  console.log(`  ✓ MedicalRecordAnchor deployed at: ${anchorAddr}`);

  // 4. Submit patient medical records
  console.log("\n[4/6] Registering medical records on PRIVATE chain...");
  const recordsToRegister = [
    { patientId: 101, code: "U07.1", hash: "0x" + ethers.keccak256(ethers.toUtf8Bytes("plan-101")).substring(2) },
    { patientId: 102, code: "J45.909", hash: "0x" + ethers.keccak256(ethers.toUtf8Bytes("plan-102")).substring(2) },
    { patientId: 103, code: "I10", hash: "0x" + ethers.keccak256(ethers.toUtf8Bytes("plan-103")).substring(2) },
    { patientId: 104, code: "E11.9", hash: "0x" + ethers.keccak256(ethers.toUtf8Bytes("plan-104")).substring(2) }
  ];

  for (const r of recordsToRegister) {
    const tx = await registry.submitRecord(r.patientId, r.code, r.hash, { gasPrice: 0 });
    const receipt = await tx.wait();
    console.log(`  ✓ Patient #${r.patientId} diagnosis: ${r.code} (block #${receipt.blockNumber})`);
  }

  const count = await registry.recordCount();
  console.log(`  Total medical records: ${count}`);

  // 5. Calculate and Anchor Merkle Root
  console.log("\n[5/6] Simulating anchor relay (Private -> Public)...");
  const leaves = [];
  for (let i = 0; i < Number(count); i++) {
    const r = await registry.records(i);
    // Hash medical record fields to calculate Merkle leaf
    const leaf = ethers.keccak256(
      ethers.AbiCoder.defaultAbiCoder().encode(
        ["uint256", "string", "string", "address", "bool"],
        [r.patientId, r.diagnosisCode, r.treatmentHash, r.doctor, r.active]
      )
    );
    leaves.push(leaf);
  }

  // Merkle root computation
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
  console.log(`  ✓ Computed Merkle root: ${merkleRoot}`);

  // Submit to public chain
  const anchorTx = await anchor.submitAnchor(merkleRoot, privateBlock, { gasPrice: 0 });
  await anchorTx.wait();
  console.log(`  ✓ Anchor submitted successfully to public chain!`);

  // 6. Verification
  console.log("\n[6/6] Verifying anchored data on PUBLIC chain...");
  const latest = await anchor.latest();
  const rootsMatch = latest.merkleRoot === merkleRoot;

  console.log(`  Latest Anchor Merkle Root: ${latest.merkleRoot}`);
  console.log(`  Private Block Anchored:    ${latest.privateBlockNumber}`);
  console.log(`  Anchor Timestamp:          ${new Date(Number(latest.timestamp) * 1000).toISOString()}`);
  console.log(`\n  Cross-chain validation:    ${rootsMatch ? "✅ PASS" : "❌ FAIL"}`);

  console.log("=" .repeat(60));
  if (rootsMatch) {
    console.log("  🎉 SUCCESS: Dual-chain healthcare integrity verified!");
    
    // Write runtime deployment configuration for API Gateway integration
    const deploymentInfo = {
      timestamp: new Date().toISOString(),
      private: {
        chainId: Number(privateChain.chainId),
        MedicalRecordRegistry: regAddr
      },
      public: {
        chainId: Number(publicChain.chainId),
        MedicalRecordAnchor: anchorAddr
      }
    };
    const outPath = path.join(__dirname, "..", "deployment.json");
    fs.writeFileSync(outPath, JSON.stringify(deploymentInfo, null, 2));
    console.log(`  Deployment metadata saved: ${outPath}`);
  } else {
    process.exit(1);
  }
}

main().catch(err => {
  console.error("❌ E2E execution failed:", err);
  process.exit(1);
});
