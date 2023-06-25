const Vesting = artifacts.require("BraqVesting");
const TOKEN_CONTRACT_ADDRESS = "0x75bA3ec8A8163C35c4061BD13A17Ef13F812cAc1";
const SALE_CONTRACT_ADDRESS = "0x4A8A584FdD48d157Ad851B172D7775C3800A190f";
const listingsAddress = "0x23FcC07b3286b37440988D95714952Bd3108Aa61";
const marketingAddress = "0xce693C85a4C2c8362eb85Af9dAdc91E6A4040378";

module.exports = async function (deployer) {
  deployer.deploy(Vesting, TOKEN_CONTRACT_ADDRESS, listingsAddress, marketingAddress);
}