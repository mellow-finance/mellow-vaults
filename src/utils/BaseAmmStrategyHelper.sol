// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../vaults/ERC20RootVault.sol";
import "../strategies/BaseAmmStrategy.sol";

import "forge-std/src/console2.sol";

contract BaseAmmStrategyHelper {
    uint256 public constant Q96 = 2**96;

    function _calculateTargetRatioX96(
        uint160 sqrtPriceX96,
        uint256 priceX96,
        BaseAmmStrategy.Position[] memory target
    ) private pure returns (uint256 targetRatioX96) {
        uint256 n = target.length;

        uint256[] memory amounts0 = new uint256[](n);
        uint256[] memory amounts1 = new uint256[](n);
        uint256[] memory capitals = new uint256[](n);

        uint256 totalCapital = 0;
        for (uint256 i = 0; i < n; i++) {
            if (target[i].capitalRatioX96 == 0) continue;
            (amounts0[i], amounts1[i]) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(target[i].tickLower),
                TickMath.getSqrtRatioAtTick(target[i].tickUpper),
                uint128(Q96)
            );
            capitals[i] = FullMath.mulDiv(amounts0[i], priceX96, Q96) + amounts1[i];
            totalCapital += capitals[i];
        }

        for (uint256 i = 0; i < n; i++) {
            if (target[i].capitalRatioX96 == 0) continue;
            (amounts0[0], amounts1[1]) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(target[i].tickLower),
                TickMath.getSqrtRatioAtTick(target[i].tickUpper),
                uint128(Q96)
            );
            capitals[i] = FullMath.mulDiv(amounts0[i], priceX96, Q96) + amounts1[i];
            totalCapital += capitals[i];
        }
        uint256[] memory targetAmounts = new uint256[](2);

        for (uint256 i = 0; i < n; i++) {
            if (target[i].capitalRatioX96 == 0) continue;
            uint256 targetCapital = FullMath.mulDiv(totalCapital, target[i].capitalRatioX96, Q96);
            if (targetCapital != capitals[i]) {
                amounts0[i] = FullMath.mulDiv(targetCapital, amounts0[i], capitals[i]);
                amounts1[i] = FullMath.mulDiv(targetCapital, amounts1[i], capitals[i]);
            }

            targetAmounts[0] += amounts0[i];
            targetAmounts[1] += amounts1[i];
        }

        return
            FullMath.mulDiv(targetAmounts[1], Q96, FullMath.mulDiv(targetAmounts[0], priceX96, Q96) + targetAmounts[1]);
    }

    function calculateSwapAmounts(
        uint160 sqrtPriceX96,
        BaseAmmStrategy.Position[] memory target,
        IERC20RootVault rootVault
    )
        external
        view
        returns (
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 amountOutMin
        )
    {
        address[] memory tokens = rootVault.vaultTokens();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256 targetRatioOfToken1X96 = _calculateTargetRatioX96(sqrtPriceX96, priceX96, target);
        (uint256[] memory tvl, ) = rootVault.tvl();
        uint256 currentRatioOfToken1X96 = FullMath.mulDiv(tvl[1], Q96, FullMath.mulDiv(tvl[0], priceX96, Q96) + tvl[1]);

        uint256 feesX96 = FullMath.mulDiv(Q96, uint256(int256(500)), 1e6);
        uint256 targetRatioOfToken0X96 = Q96 - targetRatioOfToken1X96;

        if (currentRatioOfToken1X96 > targetRatioOfToken1X96) {
            tokenIn = tokens[1];
            tokenOut = tokens[0];
            // (dx * y0 - dy * x0 * p) / (1 - dy * fee)
            uint256 invertedPriceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(tvl[1], targetRatioOfToken0X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken1X96, tvl[0], invertedPriceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken1X96, feesX96, Q96)
            );
            amountOutMin = FullMath.mulDiv(amountIn, invertedPriceX96, Q96);
        } else {
            // (dy * x0 - dx * y0 / p) / (1 - dx * fee)
            tokenIn = tokens[0];
            tokenOut = tokens[1];
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(tvl[0], targetRatioOfToken1X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken0X96, tvl[1], priceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken0X96, feesX96, Q96)
            );
            amountOutMin = FullMath.mulDiv(amountIn, priceX96, Q96);
        }
    }
}
