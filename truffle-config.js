// Allows us to use ES6 in our migrations and tests.
require('babel-register');
const HDWalletProvider = require("@truffle/hdwallet-provider");
require('dotenv').config();
const walletPrivateKey = process.env.WALLET_PRIVATE_KEY;
const etherScanPrivateKey = process.env.ETHERSCAN_PRIVATE_KEY;

module.exports = {
  networks: {
    mainnet: {
      provider: function () {
        return new HDWalletProvider([walletPrivateKey], "https://mainnet.infura.io/v3/cc8cc7e34bb440b19e75b2910913a25e")
      },
      network_id: 1,
      networkCheckTimeout: 60000,
    },
    testnet: {
      provider: function () {
        return new HDWalletProvider([walletPrivateKey], 'https://sepolia.infura.io/v3/cc8cc7e34bb440b19e75b2910913a25e')
      },
      network_id: 11155111,
      networkCheckTimeout: 60000,
      /*host: "178.25.19.88", // Random IP for example purposes (do not use)
      port: 80,
      network_id: 1,        // Ethereum public network,
      */
    },
    development: {
      host: '127.0.0.1',
      port: 8545,
      network_id: '*'
    }
  },
  compilers: {
    solc: {
      version: "^0.8.9",
      settings: {
        optimizer: {
          enabled: true,
          runs: 1500
        }
      }
    }
  },
  plugins: [
    'truffle-plugin-verify'
  ],
  api_keys: {
    etherscan: etherScanPrivateKey
  }
}