// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/// @author Vladislav Lenskii
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestNFT is ERC721, Ownable {

    constructor() ERC721("TestNFT", "TST") {}
    /**    
     * @notice Minting function 
     * @param _to any address that can hold NFTs
     * @param _id Id of the NFT to be minted
     * @dev Check if NFT is minted using the ownerOf method in "Read Contract" section
     */
    function mint(
    address _to,
    uint256 _id 
    ) external { 
        require(_to != address(0), "Error: Insert a valid address"); 
        _safeMint(_to, _id, "");
    }
    
}