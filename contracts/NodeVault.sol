// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./interfaces/INftVault.sol";

contract NodeVault is IERC721, ERC721 {
    uint256 private _topNft;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(INftVault).interfaceId || super.supportsInterface(interfaceId);
    }
}
