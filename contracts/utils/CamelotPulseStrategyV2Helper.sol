// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../strategies/CamelotPulseStrategyV2.sol";

contract CamelotPulseStrategyV2Helper {
    uint256 public constant Q96 = 2**96;
    uint256 public constant D6 = 10**6;

    function getStrategyParams(CamelotPulseStrategyV2 strategy)
        public
        view
        returns (
            CamelotPulseStrategyV2.ImmutableParams memory immutableParams,
            CamelotPulseStrategyV2.MutableParams memory mutableParams
        )
    {
        {
            (IERC20Vault erc20Vault, ICamelotVault camelotVault, address router) = strategy.immutableParams();
            immutableParams = CamelotPulseStrategyV2.ImmutableParams({
                erc20Vault: erc20Vault,
                camelotVault: camelotVault,
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
            mutableParams = CamelotPulseStrategyV2.MutableParams({
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
        CamelotPulseStrategyV2.MutableParams memory mutableParams_,
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

        uint256 feesX96 = FullMath.mulDiv(Q96, uint256(int256(mutableParams_.priceImpactD6)), D6);

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

    function calculateAmountForSwap(CamelotPulseStrategyV2 strategy)
        public
        view
        returns (
            uint256 amountIn,
            address from,
            address to,
            IERC20Vault erc20Vault
        )
    {
        (
            CamelotPulseStrategyV2.ImmutableParams memory immutableParams,
            CamelotPulseStrategyV2.MutableParams memory mutableParams
        ) = getStrategyParams(strategy);

        IAlgebraPool pool = strategy.algebraPool();
        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = pool.globalState();
        erc20Vault = immutableParams.erc20Vault;
        uint256 targetRatioOfToken1X96;
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256[] memory delta = new uint256[](2);
        {
            (CamelotPulseStrategyV2.Interval memory interval, bool neededNewInterval) = strategy.calculateNewPosition(
                mutableParams,
                spotTick,
                pool,
                immutableParams.camelotVault.positionNft()
            );

            ICamelotVault vault = immutableParams.camelotVault;
            (delta, ) = vault.tvl();
            if (!neededNewInterval) {
                ICamelotHelper helper = vault.helper();
                (, , , , , , uint128 liquidity, , , , ) = vault.positionManager().positions(vault.positionNft());
                (uint256 amount0, uint256 amount1) = helper.liquidityToTokenAmounts(
                    vault.positionNft(),
                    sqrtPriceX96,
                    liquidity
                );
                delta[0] -= amount0;
                delta[1] -= amount1;
            }
            targetRatioOfToken1X96 = strategy.calculateTargetRatioOfToken1(interval, sqrtPriceX96, priceX96);
        }

        uint256 tokenInIndex;
        (amountIn, tokenInIndex) = _calculateAmountsForSwap(
            targetRatioOfToken1X96,
            erc20Vault,
            priceX96,
            mutableParams,
            delta
        );

        from = immutableParams.tokens[tokenInIndex];
        to = immutableParams.tokens[tokenInIndex ^ 1];
        erc20Vault = immutableParams.erc20Vault;
    }
}
