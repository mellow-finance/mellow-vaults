// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../strategies/PancakeSwapPulseStrategyV2.sol";
import "../interfaces/external/pancakeswap/libraries/PositionValue.sol";
import "../interfaces/external/pancakeswap/ISmartRouter.sol";

contract TestPancakeHelper {
    uint256 public constant Q96 = 2 ** 96;

    function getStrategyParams(
        PancakeSwapPulseStrategyV2 strategy
    )
        public
        view
        returns (
            PancakeSwapPulseStrategyV2.ImmutableParams memory immutableParams,
            PancakeSwapPulseStrategyV2.MutableParams memory mutableParams
        )
    {
        {
            (IERC20Vault erc20Vault, IPancakeSwapVault pancakeSwapVault, address router) = strategy.immutableParams();
            immutableParams = PancakeSwapPulseStrategyV2.ImmutableParams({
                erc20Vault: erc20Vault,
                pancakeSwapVault: pancakeSwapVault,
                router: router,
                tokens: erc20Vault.vaultTokens()
            });
        }
        {
            (
                int24 priceImpactD6,
                int24 defaultIntervalWidth,
                int24 maxPositionLengthInTicks,
                int24 maxDeviationForVaultPool,
                uint32 timespanForAverageTick,
                uint256 neighborhoodFactorD,
                uint256 extensionFactorD,
                uint256 swapSlippageD,
                uint256 swappingAmountsCoefficientD
            ) = strategy.mutableParams();
            mutableParams = PancakeSwapPulseStrategyV2.MutableParams({
                priceImpactD6: priceImpactD6,
                defaultIntervalWidth: defaultIntervalWidth,
                maxPositionLengthInTicks: maxPositionLengthInTicks,
                maxDeviationForVaultPool: maxDeviationForVaultPool,
                timespanForAverageTick: timespanForAverageTick,
                neighborhoodFactorD: neighborhoodFactorD,
                extensionFactorD: extensionFactorD,
                swapSlippageD: swapSlippageD,
                swappingAmountsCoefficientD: swappingAmountsCoefficientD,
                minSwapAmounts: new uint256[](2)
            });
        }
    }

    function _calculateAmountsForSwap(
        uint256 targetRatioOfToken1X96,
        IERC20Vault erc20Vault,
        uint256 priceX96,
        PancakeSwapPulseStrategyV2.MutableParams memory mutableParams,
        uint256[] memory delta
    ) private view returns (uint256 amountIn, uint256 tokenInIndex) {
        uint256 targetRatioOfToken0X96 = Q96 - targetRatioOfToken1X96;
        (uint256[] memory currentAmounts, ) = erc20Vault.tvl();
        for (uint256 i = 0; i < 2; i++) {
            currentAmounts[i] += delta[i];
        }
        uint256 currentRatioOfToken1X96 = FullMath.mulDiv(
            currentAmounts[1],
            Q96,
            currentAmounts[1] + FullMath.mulDiv(currentAmounts[0], priceX96, Q96)
        );

        uint256 feesX96 = FullMath.mulDiv(Q96, uint256(int256(mutableParams.priceImpactD6)), 10 ** 6);
        if (currentRatioOfToken1X96 > targetRatioOfToken1X96) {
            tokenInIndex = 1;
            // (dx * y0 - dy * x0 * p) / (1 - dy * fee)
            uint256 invertedPriceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(currentAmounts[1], targetRatioOfToken0X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken1X96, currentAmounts[0], invertedPriceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken1X96, feesX96, Q96)
            );
        } else {
            // (dy * x0 - dx * y0 / p) / (1 - dx * fee)
            tokenInIndex = 0;
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(currentAmounts[0], targetRatioOfToken1X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken0X96, currentAmounts[1], priceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken0X96, feesX96, Q96)
            );
        }
        if (amountIn > currentAmounts[tokenInIndex]) {
            amountIn = currentAmounts[tokenInIndex];
        }
    }

    function calculateAmountForSwap(
        PancakeSwapPulseStrategyV2 strategy
    ) public view returns (bool neededNewInterval, bytes memory swapData) {
        (
            PancakeSwapPulseStrategyV2.ImmutableParams memory immutableParams,
            PancakeSwapPulseStrategyV2.MutableParams memory mutableParams
        ) = getStrategyParams(strategy);

        IPancakeV3Pool pool = IPancakeV3Pool(immutableParams.pancakeSwapVault.pool());
        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = pool.slot0();
        uint256 targetRatioOfToken1X96;
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256[] memory delta = new uint256[](2);
        {
            PancakeSwapPulseStrategyV2.Interval memory interval;
            (interval, neededNewInterval) = strategy.calculateNewPosition(
                mutableParams,
                spotTick,
                pool,
                immutableParams.pancakeSwapVault.uniV3Nft()
            );

            if (neededNewInterval) {
                (delta, ) = immutableParams.pancakeSwapVault.tvl();
            } else {
                (delta[0], delta[1]) = PositionValue.fees(
                    immutableParams.pancakeSwapVault.positionManager(),
                    immutableParams.pancakeSwapVault.uniV3Nft()
                );
            }
            targetRatioOfToken1X96 = strategy.calculateTargetRatioOfToken1(interval, sqrtPriceX96, priceX96);
        }

        (uint256 amountIn, uint256 tokenInIndex) = _calculateAmountsForSwap(
            targetRatioOfToken1X96,
            immutableParams.erc20Vault,
            priceX96,
            mutableParams,
            delta
        );
        swapData = abi.encodeWithSelector(
            ISmartRouter.exactInputSingle.selector,
            ISmartRouter.ExactInputSingleParams({
                tokenIn: immutableParams.tokens[tokenInIndex],
                tokenOut: immutableParams.tokens[tokenInIndex ^ 1],
                fee: immutableParams.pancakeSwapVault.pool().fee(),
                recipient: address(immutableParams.erc20Vault),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }
}
