const TestNFT = artifacts.require("TestNFT");

module.exports = async function (deployer) {
  deployer.deploy(TestNFT);
}