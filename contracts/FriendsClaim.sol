// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBraqFriends {
    function balanceOf(address holder) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract FriendsClaim is Ownable {
    // tokenId => (quarter => claimed)
    // further q stands for quarter 
    mapping(uint32 => mapping(uint8 => bool)) public claimed;
    mapping(uint8 => uint256) public fundingTime;
    uint8 public currentQuarter = 0; 
    event TokensClaimed(address indexed user, uint256 tokensAmount);
    bool isActive =true;

    address public BraqTokenContractAddress;
    IERC20 private BraqTokenInstance;
    address public BraqFriendsContractAdress;
    IBraqFriends private BraqFriendsInstance;

    function resetQuarter(uint8 q) external onlyOwner {
        require(q > 0 && q < 5);
        require(block.timestamp >= fundingTime[q], "Quarter did not start yet. It is too early");
        currentQuarter = q;
    }

    constructor(address _tokenContract, address _braqFriendsContract) {
        BraqTokenContractAddress = _tokenContract;
        BraqTokenInstance = IERC20(BraqTokenContractAddress);

        BraqFriendsContractAdress = _braqFriendsContract;
        BraqFriendsInstance = IBraqFriends(_braqFriendsContract);

        fundingTime[1] = block.timestamp;
        fundingTime[2] = 1696086000;
        fundingTime[3] = 1704034800;
        fundingTime[4] = 1711897200;
    }

    function startClaim() external onlyOwner{
        isActive = true;
    }

    function stopClaim() external onlyOwner{
        isActive = false;
    }

    // Both contracts have 4444 tokens
    function claimTokens(uint32[] memory tokenIds) external {
        require(currentQuarter > 0 && currentQuarter < 5, "Current quarter is wrong");
        require(tokenIds.length <= BraqFriendsInstance.balanceOf(msg.sender), "Claiming more tokens than you have!");
        uint256 braqAmount = 0; // in BRAQ tokens
        for (uint32 i=0; i < tokenIds.length; i++){
            require(tokenIds[i]<= 4444 && tokenIds[i]>0, "Claiming not existing token!");
            require(!claimed[tokenIds[i]][currentQuarter], "Token already claimed");
            require(BraqFriendsInstance.ownerOf(tokenIds[i]) == msg.sender, "Claiming not owned tokens!");
            // for Braq Friends 
            if(tokenIds[i]<=2022){
                braqAmount += 2025;
            }
            else{braqAmount+= 1012;}
        }
        BraqTokenInstance.transfer(msg.sender, braqAmount * 10 ** 18);
        emit TokensClaimed(msg.sender, tokenIds.length);
    }

    // withdraw unclaimed tokens
    // amount in BRAQ 
    function withdrawTokens(uint256 amount) external onlyOwner {
        require(BraqTokenInstance.balanceOf(address(this)) >= amount * 10 ** 18, "Too much tokens to withdraw");
        BraqTokenInstance.transfer(msg.sender, amount * 10 ** 18);
    }

    function getBraqTokenAddress() external view returns(address){
        return BraqTokenContractAddress;
    }

    function getBraqMonstersAddress() external view returns(address){
        return BraqFriendsContractAdress;
    }

    function isClaimed(uint32 tokenId, uint8 q) external view returns(bool){
        return claimed[tokenId][q];
    }
}