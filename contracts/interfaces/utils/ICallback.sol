// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface ICallback {
    function rebalanceERC20UniV3Vaults(
        uint256[] memory minLowerVaultTokens,
        uint256[] memory minUpperVaultTokens,
        uint256 deadline
    ) external returns (uint256[] memory totalPulledAmounts, bool isNegativeCapitalDelta);
}
