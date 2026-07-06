require("@nomicfoundation/hardhat-toolbox");

// Deployer private key (matches pre-funded address 0xf17f52151EbEF6C7334FAD080c5704D77216b732)
const DEPLOYER_KEY = "ae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {},
    besuPrivate: {
      url: "http://127.0.0.1:18545",
      chainId: 78901,
      gasPrice: 0,
      accounts: [DEPLOYER_KEY],
      timeout: 120000
    },
    besuPublic: {
      url: "http://127.0.0.1:28545",
      chainId: 78902,
      gasPrice: 0,
      accounts: [DEPLOYER_KEY],
      timeout: 120000
    }
  }
};
