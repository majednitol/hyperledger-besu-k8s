require("@nomicfoundation/hardhat-toolbox");

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
    localhost: {
      url: "http://127.0.0.1:8545",
      accounts: ["0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f"],
      gas: 15000000,
      gasPrice: 0
    },
    besuPrivate: {
      url: process.env.PRIVATE_RPC_URL || "http://127.0.0.1:18545",
      gas: 15000000,
      gasPrice: 0,
      accounts: ["0x5f781a4e2b528b52ce168d629f4818b5a657486f37b171955646afaf7ef8213a"],
      timeout: 120000
    }
  }
};
