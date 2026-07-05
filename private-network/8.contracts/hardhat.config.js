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
      url: "http://127.0.0.1:8545"
    },
    besuPrivate: {
      url: "http://rpc-rono.besu-private.svc.cluster.local:8545",
      // Set a high gas limit suitable for our private network limits
      gas: 15000000,
      gasPrice: 0, // QBFT handles gas but standard transaction validation may require gasPrice: 0 or low value
      // Explicitly specify private key for deployer (pre-funded in genesis)
      // accounts: ["0x..."] 
    }
  }
};
