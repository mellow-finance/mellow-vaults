// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./ITokensEntity.sol";

interface INFTVault is ITokensEntity, IERC721 {
    function tokenAmounts(uint256 nft) external view returns (uint256[] memory);

    function owedTokenAmounts() external view returns (uint256[] memory);

    function totalTokenAmounts() external view returns (uint256[] memory);

    function deposit(uint256 nft, uint256[] calldata caps) external;

    function withdraw(uint256 nft, uint256[] calldata caps) external;
}
