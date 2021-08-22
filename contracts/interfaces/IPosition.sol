// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./ITokensEntity.sol";
import "./ISpatialNFT.sol";

interface IPosition is ISpatialNft, ITokensEntity, IERC721Receiver {
    function deposit(uint256 nft, uint256[] calldata tokenAmounts) external;

    function withdraw(uint256 nft, uint256[] calldata tokenAmounts) external;

    function tokenAmounts(uint256 nft) external view returns (uint256[] memory);
}
