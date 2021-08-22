// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/tokens/ERC721.sol";
import "./access/OwnerAccessControl.sol";

contract TokenCells is OwnerAccessControl, ERC721 {
    struct MutableTokenCellsGovernanceData {
        bool isPublicCreateCell;
    }
    mapping(uint256 => mapping(address => uint256)) public tokenBalances;
    mapping(uint256 => address[]) public tokens;

    uint256 private _topCellNft;

    // @dev Can claim only free tokens
    function claimTokensToCell(
        uint256 nft,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) public {}

    function disburseTokensFromCell(
        uint256 nft,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) public {}

    function createCell(address owner, address[] tokens) external returns (uint256) {}
}
