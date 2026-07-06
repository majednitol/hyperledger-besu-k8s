/**
 * Deploy RegistryAnchor to the PUBLIC Besu network.
 * Usage: npx hardhat run scripts/deploy-public.js --network besuPublic
 */
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying RegistryAnchor to PUBLIC network...");
  console.log("  Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("  Balance:", ethers.formatEther(balance), "ETH");

  const chainId = (await ethers.provider.getNetwork()).chainId;
  console.log("  Chain ID:", chainId.toString());

  // Deploy RegistryAnchor with deployer as the relayer
  const RegistryAnchor = await ethers.getContractFactory("RegistryAnchor");
  const anchor = await RegistryAnchor.deploy(deployer.address, { gasLimit: 3000000 });
  await anchor.waitForDeployment();
  const anchorAddr = await anchor.getAddress();
  console.log("  RegistryAnchor deployed at:", anchorAddr);

  // Submit a test anchor (simulating a bridge relay)
  console.log("\nSubmitting test anchor (simulating bridge relay)...");
  const testRoot = ethers.keccak256(ethers.toUtf8Bytes("test-merkle-root-block-1"));
  let tx = await anchor.submitAnchor(testRoot, 1, { gasLimit: 150000 });
  await tx.wait();
  console.log("  ✓ Anchor 0 submitted: root =", testRoot);

  // Submit a second anchor
  const testRoot2 = ethers.keccak256(ethers.toUtf8Bytes("test-merkle-root-block-10"));
  tx = await anchor.submitAnchor(testRoot2, 10, { gasLimit: 150000 });
  await tx.wait();
  console.log("  ✓ Anchor 1 submitted: root =", testRoot2);

  // Read back the data
  console.log("\nVerifying stored data...");
  const total = await anchor.totalAnchors();
  console.log("  Total anchors:", total.toString());

  const latest = await anchor.latest();
  console.log("  Latest anchor:");
  console.log("    Merkle Root:", latest.merkleRoot);
  console.log("    Private Block:", latest.privateBlockNumber.toString());
  console.log("    Timestamp:", latest.timestamp.toString());

  console.log("\n✅ Public network deployment complete!");
  console.log("   Contract address:", anchorAddr);
  return anchorAddr;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
