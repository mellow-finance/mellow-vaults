// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ITokenCells is IERC721 {
    function claimTokensToCell(
        uint256 cellNft,
        address[] memory tokensToClaim,
        uint256[] memory tokenAmounts
    ) external;

    function disburseTokensFromCell(
        uint256 cellNft,
        address to,
        address[] memory tokensToDisburse,
        uint256[] memory tokenAmounts
    ) external;

    function createCell(address[] memory cellTokens) external returns (uint256);
}
