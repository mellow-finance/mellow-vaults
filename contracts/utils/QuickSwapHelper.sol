// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/quickswap/IAlgebraPool.sol";
import "../interfaces/external/quickswap/INonfungiblePositionManager.sol";
import "../interfaces/external/quickswap/IAlgebraEternalFarming.sol";
import "../interfaces/external/quickswap/IAlgebraEternalVirtualPool.sol";
import "../interfaces/vaults/IQuickSwapVaultGovernance.sol";

import {PositionValue, LiquidityAmounts, TickMath, FullMath} from "../interfaces/external/quickswap/PositionValue.sol";

contract QuickSwapHelper {
    INonfungiblePositionManager public immutable positionManager;
    uint256 public constant Q128 = 2**128;
    uint256 public constant Q96 = 2**96;

    constructor(INonfungiblePositionManager positionManager_) {
        require(address(positionManager_) != address(0));
        positionManager = positionManager_;
    }

    function calculateTvl(
        uint256 nft,
        IQuickSwapVaultGovernance.DelayedStrategyParams memory strategyParams,
        IFarmingCenter farmingCenter,
        address token0
    ) public view returns (uint256[] memory tokenAmounts) {
        if (nft == 0) {
            return new uint256[](2);
        }
        IIncentiveKey.IncentiveKey memory key = strategyParams.key;
        (uint160 sqrtRatioX96, , , , , , ) = key.pool.globalState();
        tokenAmounts = new uint256[](2);
        (tokenAmounts[0], tokenAmounts[1]) = PositionValue.total(positionManager, nft, sqrtRatioX96);

        IAlgebraEternalFarming farming = farmingCenter.eternalFarming();

        (uint256 rewardAmount, uint256 bonusRewardAmount) = calculateCollectableRewards(farming, key, nft);
        rewardAmount += farming.rewards(address(this), key.rewardToken);
        bonusRewardAmount += farming.rewards(address(this), key.bonusRewardToken);

        rewardAmount = convertTokenToUnderlying(
            rewardAmount,
            address(key.rewardToken),
            strategyParams.rewardTokenToUnderlying
        );
        bonusRewardAmount = convertTokenToUnderlying(
            bonusRewardAmount,
            address(key.rewardToken),
            strategyParams.bonusTokenToUnderlying
        );

        if (address(strategyParams.rewardTokenToUnderlying) == token0) {
            tokenAmounts[0] += rewardAmount;
        } else {
            tokenAmounts[1] += rewardAmount;
        }

        if (address(strategyParams.bonusTokenToUnderlying) == token0) {
            tokenAmounts[0] += bonusRewardAmount;
        } else {
            tokenAmounts[1] += bonusRewardAmount;
        }
    }

    function liquidityToTokenAmounts(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint128 liquidity
    ) public view returns (uint256 amount0, uint256 amount1) {
        (, , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(nft);
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liquidity
        );
    }

    function tokenAmountsToLiquidity(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint256[] memory amounts
    ) public view returns (uint128 liquidity) {
        (, , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(nft);
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            amounts[0],
            amounts[1]
        );
    }

    function tokenAmountsToMaxLiquidity(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint256[] memory amounts
    ) public view returns (uint128 liquidity) {
        (, , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(nft);
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amounts[0]);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amounts[0]);
            uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amounts[1]);

            liquidity = liquidity0 > liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amounts[1]);
        }
    }

    function calculateCollectableRewards(
        IAlgebraEternalFarming farming,
        IIncentiveKey.IncentiveKey memory key,
        uint256 nft
    ) public view returns (uint256 rewardAmount, uint256 bonusRewardAmount) {
        bytes32 incentiveId = keccak256(abi.encode(key));
        (uint256 totalReward, , address virtualPoolAddress, , , , ) = farming.incentives(incentiveId);
        if (totalReward == 0) {
            return (0, 0);
        }

        IAlgebraEternalVirtualPool virtualPool = IAlgebraEternalVirtualPool(virtualPoolAddress);
        (
            uint128 liquidity,
            int24 tickLower,
            int24 tickUpper,
            uint256 innerRewardGrowth0,
            uint256 innerRewardGrowth1
        ) = farming.farms(nft, incentiveId);
        if (liquidity == 0) {
            return (0, 0);
        }

        (uint256 virtualPoolInnerRewardGrowth0, uint256 virtualPoolInnerRewardGrowth1) = virtualPool
            .getInnerRewardsGrowth(tickLower, tickUpper);

        (rewardAmount, bonusRewardAmount) = (
            FullMath.mulDiv(virtualPoolInnerRewardGrowth0 - innerRewardGrowth0, liquidity, Q128),
            FullMath.mulDiv(virtualPoolInnerRewardGrowth1 - innerRewardGrowth1, liquidity, Q128)
        );
    }

    function convertTokenToUnderlying(
        uint256 amount,
        address from,
        address to
    ) public view returns (uint256) {
        if (from == to || amount == 0) return amount;
        address poolDeployer = positionManager.poolDeployer();
        IAlgebraPool pool = IAlgebraPool(PoolAddress.computeAddress(poolDeployer, PoolAddress.getPoolKey(from, to)));
        (uint160 sqrtPriceX96, , , , , , ) = pool.globalState();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (pool.token0() == to) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        }
        return FullMath.mulDiv(amount, priceX96, Q96);
    }
}
