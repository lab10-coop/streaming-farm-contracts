// SPDX-License-Identifier: AGPLv3
pragma solidity 0.7.6;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

interface IFarmNFTOwner {
    /// @dev called by the FarmNFT on transfer
    function onNFTTransfer(address from, address to, uint256 tokenId) external;

    /// @dev the FarmNFT forwards calls to tokenURI to the owner through this method
    /// @return uri The URI to be provided by the NFTs tokenURI method.
    /// If empty, the NFT contract may provide a fallback value.
    function getNftTokenURI(uint256 tokenId) external view returns (string memory uri);
}

/**
* An ERC-721 based NFT representing stakes in a farm.
* Expects to be owned by a contract implementing the IFarmNFTOwner interface.
* The owner can mint and burn tokens.
* The owner is responsible for not breaking anything when handing over ownership.
* Ownership can be handed over using the method transferOwnership() inherited by Ownable.
*/
contract FarmNFT is ERC721, Ownable {
    uint256 internal idCounter = 0;
    mapping (address => bool) permittedMinters;
    mapping (uint256 => address) tokenMinter;

    constructor() ERC721("Minerva Farm Positions", "MIVA-V2-FPOS") {}

    // Overridden transfer method invokes the owner hook for all transfers.
    // _beforeTokenTransfer() was not used because it's invoked on minting too, adding complication.
    function _transfer(address from, address to, uint256 tokenId) internal override {
        super._transfer(from, to, tokenId);

        IFarmNFTOwner owner = IFarmNFTOwner(owner());
        owner.onNFTTransfer(from, to, tokenId);
    }

    function addMinter(address minterToAdd) public onlyOwner {
        permittedMinters[minterToAdd] = true;
    }

    function removeMinter(address minterToRemove) public onlyOwner {
        permittedMinters[minterToRemove] = false;
    }

    function mint(address to) public /*onlyOwner*/ returns(uint256 tokenId) {
        require(permittedMinters[msg.sender] == true, "FarmNFT: no minting permission");
        _safeMint(to, idCounter);
        tokenMinter[idCounter] = msg.sender;
        return idCounter++;
    }

    function burn(uint256 tokenId) public /*onlyOwner*/ {
        require(msg.sender == tokenMinter[tokenId], "FarmNFT: only minter can burn");
        _burn(tokenId);
    }

    // forwards the call to the owner which is expected to have the relevant token specific data
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        IFarmNFTOwner minter = IFarmNFTOwner(tokenMinter[tokenId]);
        return minter.getNftTokenURI(tokenId);
    }
}