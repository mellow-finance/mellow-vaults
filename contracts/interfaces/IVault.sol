// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IVault {
    function vaultTokens() external view returns (address[] memory);

    function isVaultToken(address token) external view returns (bool);

    function vaultLimits() external view returns (uint256[] memory);

    function tvl() external view returns (address[] memory tokens, uint256[] memory tokenAmounts);

    function push(address[] calldata tokens, uint256[] calldata tokenAmounts)
        external
        returns (uint256[] memory actualTokenAmounts);

    function transferAndPush(
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

    function collectEarnings(address to, address[] calldata tokens)
        external
        returns (uint256[] memory collectedEarnings);

    function reclaimTokens(address to, address[] calldata tokens) external;

    event Push(uint256[] tokenAmounts);
    event Pull(address to, uint256[] tokenAmounts);
    event CollectEarnings(address to, address[] tokens, uint256[] tokenAmounts);
    event ReclaimTokens(address to, address[] tokens, uint256[] tokenAmounts);
}
