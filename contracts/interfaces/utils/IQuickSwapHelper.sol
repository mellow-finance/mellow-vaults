// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../external/quickswap/IAlgebraEternalFarming.sol";
import "../external/quickswap/IAlgebraEternalVirtualPool.sol";
import "../external/quickswap/IAlgebraFactory.sol";
import "../external/quickswap/IAlgebraPool.sol";
import "../external/quickswap/IAlgebraNonfungiblePositionManager.sol";
import "../vaults/IQuickSwapVaultGovernance.sol";

interface IQuickSwapHelper {
    function calculateTvl(
        uint256 nft,
        IQuickSwapVaultGovernance.DelayedStrategyParams memory strategyParams,
        IFarmingCenter farmingCenter,
        address token0
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

    function calculateCollectableRewards(
        IAlgebraEternalFarming farming,
        IIncentiveKey.IncentiveKey memory key,
        uint256 nft
    ) external view returns (uint256 rewardAmount, uint256 bonusRewardAmount);

    function convertTokenToUnderlying(
        uint256 amount,
        address from,
        address to
    ) external view returns (uint256);
}
