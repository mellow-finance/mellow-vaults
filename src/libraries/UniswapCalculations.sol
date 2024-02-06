// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./external/LiquidityAmounts.sol";

/*
    Auxiliary library for Uniswap calculations.
*/
library UniswapCalculations {
    uint256 public constant Q96 = 2**96;

    /// @dev Structure containing information about prices at position boundaries and spot price.
    /// @param sqrtLowerPriceX96 The square root price of the lower boundary of the position.
    /// @param sqrtUpperPriceX96 The square root price of the upper boundary of the position.
    /// @param sqrtPriceX96 The square root spot price of the position.
    struct PositionParams {
        uint160 sqrtLowerPriceX96;
        uint160 sqrtUpperPriceX96;
        uint160 sqrtPriceX96;
    }

    /// @dev Function for calculating the proportion of token1 to total capital in a given position.
    /// @param position The parameters of the position.
    /// @param priceX96 The price of the token.
    /// @return targetRatioOfToken1X96 The target ratio of token1 in the position.
    function calculateTargetRatioOfToken1(PositionParams memory position, uint256 priceX96)
        public
        pure
        returns (uint256 targetRatioOfToken1X96)
    {
        if (position.sqrtLowerPriceX96 >= position.sqrtPriceX96) {
            return 0;
        } else if (position.sqrtUpperPriceX96 <= position.sqrtPriceX96) {
            return Q96;
        }

        (uint256 x, uint256 y) = LiquidityAmounts.getAmountsForLiquidity(
            position.sqrtPriceX96,
            position.sqrtLowerPriceX96,
            position.sqrtUpperPriceX96,
            uint128(Q96)
        );

        targetRatioOfToken1X96 = FullMath.mulDiv(y, Q96, FullMath.mulDiv(x, priceX96, Q96) + y);
    }

    /// @dev Function for calculating the amount of tokens for a swap, for subsequent deposit without remainder into a given position.
    /// @param position The parameters of the position.
    /// @param amount0 The amount of token0.
    /// @param amount1 The amount of token1.
    /// @param swapFee The swap fee.
    /// @return tokenInIndex The index of the token to be swapped.
    /// @return amountIn The amount of token to be swapped in.
    function calculateAmountsForSwap(
        PositionParams memory position,
        uint256 amount0,
        uint256 amount1,
        uint24 swapFee
    ) external pure returns (uint256 tokenInIndex, uint256 amountIn) {
        uint256 priceX96 = FullMath.mulDiv(position.sqrtPriceX96, position.sqrtPriceX96, Q96);

        uint256 targetRatioOfToken1X96 = calculateTargetRatioOfToken1(position, priceX96);

        uint256 targetRatioOfToken0X96 = Q96 - targetRatioOfToken1X96;
        uint256 currentRatioOfToken1X96 = FullMath.mulDiv(
            amount1,
            Q96,
            amount1 + FullMath.mulDiv(amount0, priceX96, Q96)
        );

        uint256 feesX96 = FullMath.mulDiv(Q96, uint256(swapFee), 10**6);

        if (currentRatioOfToken1X96 > targetRatioOfToken1X96) {
            tokenInIndex = 1;
            // (dx * y0 - dy * x0 * p) / (1 - dy * fee)
            uint256 invertedPriceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(amount1, targetRatioOfToken0X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken1X96, amount0, invertedPriceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken1X96, feesX96, Q96)
            );
        } else {
            // (dy * x0 - dx * y0 / p) / (1 - dx * fee)
            tokenInIndex = 0;
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(amount0, targetRatioOfToken1X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken0X96, amount1, priceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken0X96, feesX96, Q96)
            );
        }
    }
}
