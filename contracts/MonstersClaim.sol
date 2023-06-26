// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBraqMonsters {
    function balanceOf(address holder) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract MonstersClaim is Ownable {
    // tokenId => (quarter => claimed)
    // further q stands for quarter 
    mapping(uint32 => mapping(uint8 => bool)) public claimed;
    mapping(uint8 => uint256) public fundingTime;
    uint8 public currentQuarter = 0; 
    event TokensClaimed(address indexed user, uint256 tokensAmount);

    address public BraqTokenContractAddress;
    IERC20 private BraqTokenInstance;
    address public BraqMonstersContractAdress;
    IBraqMonsters private BraqMonstersInstance;

    function resetQuarter(uint8 q) external onlyOwner {
        require(q > 0 && q < 5);
        require(block.timestamp >= fundingTime[q], "Quarter did not start yet. It's too early");
        currentQuarter = q;
    }

    constructor(address _tokenContract, address _braqMonstersContract) {
        BraqTokenContractAddress = _tokenContract;
        BraqTokenInstance = IERC20(BraqTokenContractAddress);

        BraqMonstersContractAdress = _braqMonstersContract;
        BraqMonstersInstance = IBraqMonsters(_braqMonstersContract);

        fundingTime[0] = block.timestamp;
        fundingTime[1] = 1688137200;
        fundingTime[2] = 1696086000;
        fundingTime[3] = 1704034800;
        fundingTime[4] = 1711897200;
    }

    // Both contracts have 4444 tokens
    function claimTokens(uint32[] memory tokenIds) external {
        require(currentQuarter > 0 && currentQuarter < 5);
        require(tokenIds.length <= BraqMonstersInstance.balanceOf(msg.sender), "Claiming more tokens than you have!");
        uint256 braqAmount = 0; // in BRAQ tokens
        for (uint32 i=0; i < tokenIds.length; i++){
            require(tokenIds[i]<= 4444 && tokenIds[i]>0, "Claiming not existing token!");
            require(!claimed[tokenIds[i]][currentQuarter], "Token already claimed");
            require(BraqMonstersInstance.ownerOf(tokenIds[i]) == msg.sender, "Claiming not owned tokens!");
            braqAmount += 675;
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
        return BraqMonstersContractAdress;
    }

    function isClaimed(uint32 tokenId, uint8 q) external view returns(bool){
        return claimed[tokenId][q];
    }
}
