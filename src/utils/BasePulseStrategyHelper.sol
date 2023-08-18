// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../strategies/BasePulseStrategy.sol";
import "../libraries/external/PositionValue.sol";

contract BasePulseStrategyHelper {
    uint256 public constant Q96 = 2**96;

    function getStrategyParams(BasePulseStrategy strategy)
        public
        view
        returns (
            BasePulseStrategy.ImmutableParams memory immutableParams,
            BasePulseStrategy.MutableParams memory mutableParams
        )
    {
        {
            (IERC20Vault erc20Vault, IUniV3Vault uniV3Vault, address router) = strategy.immutableParams();
            immutableParams = BasePulseStrategy.ImmutableParams({
                erc20Vault: erc20Vault,
                uniV3Vault: uniV3Vault,
                router: router,
                tokens: erc20Vault.vaultTokens()
            });
        }
        {
            (
                int24 priceImpactD6,
                int24 maxDeviationForVaultPool,
                uint32 timespanForAverageTick,
                uint256 swapSlippageD,
                uint256 swappingAmountsCoefficientD
            ) = strategy.mutableParams();
            mutableParams = BasePulseStrategy.MutableParams({
                priceImpactD6: priceImpactD6,
                maxDeviationForVaultPool: maxDeviationForVaultPool,
                timespanForAverageTick: timespanForAverageTick,
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
        BasePulseStrategy.MutableParams memory mutableParams,
        uint256[] memory delta
    ) private view returns (uint256 amountIn, uint256 tokenInIndex) {
        uint256 targetRatioOfToken0X96 = Q96 - targetRatioOfToken1X96;
        (uint256[] memory currentAmounts, ) = erc20Vault.tvl();
        for (uint256 i = 0; i < 2; i++) {
            currentAmounts[i] += delta[i];
        }
        if (currentAmounts[0] + currentAmounts[1] == 0) return (0, 0);
        uint256 currentRatioOfToken1X96 = FullMath.mulDiv(
            currentAmounts[1],
            Q96,
            currentAmounts[1] + FullMath.mulDiv(currentAmounts[0], priceX96, Q96)
        );

        uint256 feesX96 = FullMath.mulDiv(Q96, uint256(int256(mutableParams.priceImpactD6)), 10**6);
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

    function calculateAmountForSwap(BasePulseStrategy strategy, BasePulseStrategy.Interval memory interval)
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
            BasePulseStrategy.ImmutableParams memory immutableParams,
            BasePulseStrategy.MutableParams memory mutableParams
        ) = getStrategyParams(strategy);

        IUniswapV3Pool pool = IUniswapV3Pool(immutableParams.uniV3Vault.pool());
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        erc20Vault = immutableParams.erc20Vault;
        uint256 targetRatioOfToken1X96;
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256[] memory delta = new uint256[](2);
        {
            bool isPositionSame = strategy.compareIntervals(interval, immutableParams.uniV3Vault.uniV3Nft());
            if (!isPositionSame) {
                (delta, ) = immutableParams.uniV3Vault.tvl();
            } else {
                (delta[0], delta[1]) = PositionValue.fees(
                    immutableParams.uniV3Vault.positionManager(),
                    immutableParams.uniV3Vault.uniV3Nft()
                );
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
