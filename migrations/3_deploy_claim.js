const MonstersClaim = artifacts.require("MonstersClaim");
const FriendsClaim = artifacts.require("FriendsClaim");
const TOKEN_CONTRACT_ADDRESS = "0x75bA3ec8A8163C35c4061BD13A17Ef13F812cAc1";
const BraqMonstersContractAddress = "0x1D3279c7E6fdeBFCcbaAcaF9366ed7cf5b3e746a";
const BraqFriendsContractAddress = "0x1D3279c7E6fdeBFCcbaAcaF9366ed7cf5b3e746a";
const listingsAddress = "0x23FcC07b3286b37440988D95714952Bd3108Aa61";
const marketingAddress = "0xce693C85a4C2c8362eb85Af9dAdc91E6A4040378";

module.exports = async function (deployer) {
  deployer.deploy(MonstersClaim, TOKEN_CONTRACT_ADDRESS, BraqMonstersContractAddress);
  deployer.deploy(FriendsClaim, TOKEN_CONTRACT_ADDRESS, BraqFriendsContractAddress);
}