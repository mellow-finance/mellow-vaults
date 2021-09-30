// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IVaults is IERC721 {
    function managedTokens(uint256 nft) external view returns (address[] memory);

    function isManagedToken(uint256 nft, address token) external view returns (bool);

    function tokenLimits(uint256 nft) external view returns (uint256[] memory);

    function vaultTVL(uint256 nft) external view returns (address[] memory tokens, uint256[] memory tokenAmounts);

    function topVaultNft() external returns (uint256);

    function createVault(
        address[] memory cellTokens,
        uint256[] memory limits,
        bytes memory params
    ) external returns (uint256);

    function push(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external returns (uint256[] memory actualTokenAmounts);

    function transferAndPush(
        uint256 nft,
        address from,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external returns (uint256[] memory actualTokenAmounts);

    function pull(
        uint256 nft,
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external returns (uint256[] memory actualTokenAmounts);

    function collectEarnings(uint256 nft, address to)
        external
        returns (address[] memory tokens, uint256[] memory collectedEarnings);

    function reclaimTokens(address to, address[] calldata tokens) external;

    event CreateVault(uint256 indexed nft, address indexed owner, uint256[] limits, bytes params);
    event CollectEarnings(uint256 indexed nft, address indexed to, address[] tokens, uint256[] tokenAmounts);
    event ReclaimTokens(address indexed to, address[] tokens, uint256[] tokenAmounts);
    event LimitsUpdate(uint256 indexed nft, uint256[] newLimits);
    event Push(uint256 indexed nft, address[] tokens, uint256[] actualTokenAmounts);
    event Pull(uint256 indexed nft, address indexed to, address[] tokens, uint256[] actualTokenAmounts);
}
