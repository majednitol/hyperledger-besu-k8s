/**
 * Deploy PrefixRegistry to the PRIVATE Besu network.
 * Usage: npx hardhat run scripts/deploy-private.js --network besuPrivate
 */
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying PrefixRegistry to PRIVATE network...");
  console.log("  Deployer:", deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("  Balance:", ethers.formatEther(balance), "ETH");

  const chainId = (await ethers.provider.getNetwork()).chainId;
  console.log("  Chain ID:", chainId.toString());

  const PrefixRegistry = await ethers.getContractFactory("PrefixRegistry");
  const registry = await PrefixRegistry.deploy();
  await registry.waitForDeployment();
  const registryAddr = await registry.getAddress();
  console.log("  PrefixRegistry deployed at:", registryAddr);

  // Register some test prefixes
  console.log("\nRegistering test prefixes...");
  let tx;

  tx = await registry.registerPrefix("192.168.0.0/16", "APNIC");
  await tx.wait();
  console.log("  ✓ Registered 192.168.0.0/16 (APNIC)");

  tx = await registry.registerPrefix("41.0.0.0/8", "AFRINIC");
  await tx.wait();
  console.log("  ✓ Registered 41.0.0.0/8 (AFRINIC)");

  // Read back the data
  console.log("\nVerifying stored data...");
  const total = await registry.totalPrefixes();
  console.log("  Total prefixes:", total.toString());

  for (let i = 0; i < Number(total); i++) {
    const p = await registry.getPrefix(i);
    console.log(`  [${i}] ${p.cidr} | ${p.rir} | holder: ${p.holder} | active: ${p.active}`);
  }

  console.log("\n✅ Private network deployment complete!");
  console.log("   Contract address:", registryAddr);
  return registryAddr;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
