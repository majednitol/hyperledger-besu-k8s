const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer Address:", deployer.address);

  // Deploy MedicalRecordAnchor with the dedicated relayer address
  const MedicalRecordAnchor = await ethers.getContractFactory("MedicalRecordAnchor");
  const contract = await MedicalRecordAnchor.deploy("0xF6110Fb284A80a52137394082Fc22266AcDd8Dc8", { gasLimit: 5000000 });
  await contract.waitForDeployment();
  console.log("MedicalRecordAnchor deployed to:", await contract.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
