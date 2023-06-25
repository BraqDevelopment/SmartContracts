// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestNFT is ERC721, Ownable {
    uint256 public publicSaleSupply = 3750000;

    constructor() ERC721("TestBRAQ", "TST") {}
        
    function mint(
    address _to,
    uint256 _id 
    ) external { 
        require(_to != address(0), "Error: Insert a valid address"); 
        _safeMint(_to, _id, "");
    }
    
}