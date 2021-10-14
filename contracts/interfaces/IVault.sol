// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernance.sol";

interface IVault {
    function vaultGovernance() external view returns (IVaultGovernance);

    function tvl() external view returns (uint256[] memory tokenAmounts);

    function earnings() external view returns (uint256[] memory tokenAmounts);

    function push(
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        bool optimized,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts);

    function transferAndPush(
        address from,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        bool optimized,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts);

    function pull(
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        bool optimized,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts);

    function collectEarnings(address to, bytes memory options) external returns (uint256[] memory collectedEarnings);

    function reclaimTokens(address to, address[] calldata tokens) external;

    event Push(uint256[] tokenAmounts);
    event Pull(address to, uint256[] tokenAmounts);
    event CollectEarnings(address to, uint256[] tokenAmounts);
    event ReclaimTokens(address to, address[] tokens, uint256[] tokenAmounts);
}
