// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ICells is IERC721 {
    function managedTokens(uint256 nft) external view returns (address[] memory);

    function isManagedToken(uint256 nft, address token) external view returns (bool);

    function createCell(address[] memory cellTokens, bytes memory params) external returns (uint256);
}
