const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // 1. Deploy Admin contract
  console.log("Deploying Admin contract...");
  const Admin = await ethers.getContractFactory("Admin");
  const adminContract = await Admin.deploy();
  await adminContract.waitForDeployment();
  const adminAddress = await adminContract.getAddress();
  console.log("Admin contract deployed to:", adminAddress);

  // 2. Deploy NodeRules contract
  console.log("Deploying NodeRules contract...");
  const NodeRules = await ethers.getContractFactory("NodeRules");
  const nodeRules = await NodeRules.deploy(adminAddress);
  await nodeRules.waitForDeployment();
  const nodeRulesAddress = await nodeRules.getAddress();
  console.log("NodeRules contract deployed to:", nodeRulesAddress);

  // 3. Deploy AccountRules contract
  console.log("Deploying AccountRules contract...");
  const AccountRules = await ethers.getContractFactory("AccountRules");
  const accountRules = await AccountRules.deploy(adminAddress);
  await accountRules.waitForDeployment();
  const accountRulesAddress = await accountRules.getAddress();
  console.log("AccountRules contract deployed to:", accountRulesAddress);

  // 4. Configure Ingress contracts
  const nodeIngressAddress = "0x0000000000000000000000000000000000009999";
  const accountIngressAddress = "0x0000000000000000000000000000000000008888";

  console.log("Checking if Ingress contracts are pre-allocated...");
  const nodeIngressCode = await ethers.provider.getCode(nodeIngressAddress);
  const accountIngressCode = await ethers.provider.getCode(accountIngressAddress);

  let nodeIngress, accountIngress;

  if (nodeIngressCode !== "0x" && nodeIngressCode !== "0x00") {
    console.log("   NodeIngress exists at fixed address:", nodeIngressAddress);
    nodeIngress = await ethers.getContractAt("NodeIngress", nodeIngressAddress);
    const tx = await nodeIngress.setRulesAddress(nodeRulesAddress);
    await tx.wait();
    console.log("   Associated NodeRules with pre-allocated NodeIngress");
  } else {
    console.log("   NodeIngress not found at fixed address. Deploying a new one dynamically (Staging/Local Mode)...");
    const NodeIngress = await ethers.getContractFactory("NodeIngress");
    nodeIngress = await NodeIngress.deploy();
    await nodeIngress.waitForDeployment();
    const dynamicNodeIngressAddress = await nodeIngress.getAddress();
    console.log("   Dynamic NodeIngress deployed to:", dynamicNodeIngressAddress);
    const tx = await nodeIngress.setRulesAddress(nodeRulesAddress);
    await tx.wait();
  }

  if (accountIngressCode !== "0x" && accountIngressCode !== "0x00") {
    console.log("   AccountIngress exists at fixed address:", accountIngressAddress);
    accountIngress = await ethers.getContractAt("AccountIngress", accountIngressAddress);
    const tx = await accountIngress.setRulesAddress(accountRulesAddress);
    await tx.wait();
    console.log("   Associated AccountRules with pre-allocated AccountIngress");
  } else {
    console.log("   AccountIngress not found at fixed address. Deploying a new one dynamically (Staging/Local Mode)...");
    const AccountIngress = await ethers.getContractFactory("AccountIngress");
    accountIngress = await AccountIngress.deploy();
    await accountIngress.waitForDeployment();
    const dynamicAccountIngressAddress = await accountIngress.getAddress();
    console.log("   Dynamic AccountIngress deployed to:", dynamicAccountIngressAddress);
    const tx = await accountIngress.setRulesAddress(accountRulesAddress);
    await tx.wait();
  }

  // 5. Deploy PrefixRegistry
  console.log("Deploying PrefixRegistry contract...");
  const PrefixRegistry = await ethers.getContractFactory("PrefixRegistry");
  const prefixRegistry = await PrefixRegistry.deploy();
  await prefixRegistry.waitForDeployment();
  const prefixRegistryAddress = await prefixRegistry.getAddress();
  console.log("PrefixRegistry contract deployed to:", prefixRegistryAddress);

  console.log("");
  console.log("=========================================");
  console.log("Deployment Complete!");
  console.log("Admin contract:", adminAddress);
  console.log("NodeRules:", nodeRulesAddress);
  console.log("AccountRules:", accountRulesAddress);
  console.log("PrefixRegistry:", prefixRegistryAddress);
  console.log("=========================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
