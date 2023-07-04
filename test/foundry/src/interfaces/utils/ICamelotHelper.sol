// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../external/algebrav2/IAlgebraFactory.sol";
import "../external/algebrav2/IAlgebraPool.sol";
import "../external/algebrav2/IAlgebraNonfungiblePositionManager.sol";
import "../vaults/ICamelotVaultGovernance.sol";

interface ICamelotHelper {
    function calculateTvl(
        uint256 nft
    ) external view returns (uint256[] memory tokenAmounts);

    function liquidityToTokenAmounts(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint128 liquidity
    ) external view returns (uint256 amount0, uint256 amount1);

    function tokenAmountsToLiquidity(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint256[] memory amounts
    ) external view returns (uint128 liquidity);

    function tokenAmountsToMaxLiquidity(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint256[] memory amounts
    ) external view returns (uint128 liquidity);

    function calculateLiquidityToPull(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint256[] memory tokenAmounts
    ) external view returns (uint128 liquidity);
}
