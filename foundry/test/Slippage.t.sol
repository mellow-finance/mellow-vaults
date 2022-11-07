// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "../lib/forge-std/src/console2.sol";
import "./helpers/libraries/LiquidityAmounts.sol";
import "./helpers/libraries/TickMath.sol";
import "./helpers/libraries/FullMath.sol";

contract SlippageT {
    function getCapital(
        uint256 amount0,
        uint256 amount1,
        int24 currentTick
    ) internal pure returns (uint256 capital) {
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(currentTick);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 2**96);
        // TODO: check order
        return FullMath.mulDiv(amount0, priceX96, 2**96) + amount1;
    }

    function minTvl(
        int24 leftTick,
        int24 rightTick,
        int24 currentTick,
        int24 deviatedTick,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(currentTick),
            TickMath.getSqrtRatioAtTick(leftTick),
            TickMath.getSqrtRatioAtTick(rightTick),
            liquidity
        );
        {
            (uint256 tmp0, uint256 tmp1) = LiquidityAmounts.getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(deviatedTick),
                TickMath.getSqrtRatioAtTick(leftTick),
                TickMath.getSqrtRatioAtTick(rightTick),
                liquidity
            );
            if (tmp0 < amount0) {
                amount0 = tmp0;
            }
            if (tmp1 < amount1) {
                amount1 = tmp1;
            }
        }
    }

    function getMinCapital(
        int24 leftLowerTick,
        int24 leftUpperTick,
        int24 rightLowerTick,
        int24 rightUpperTick,
        int24 currentTick,
        int24 deviatedTick,
        uint128 liquidity
    ) internal pure returns (uint256 capital) {
        (uint256 amount0, uint256 amount1) = minTvl(leftLowerTick, leftUpperTick, currentTick, deviatedTick, liquidity);
        {
            (uint256 tmp0, uint256 tmp1) = minTvl(rightLowerTick, rightUpperTick, currentTick, deviatedTick, liquidity);
            amount0 += tmp0;
            amount1 += tmp1;
        }
        return getCapital(amount0, amount1, currentTick);
    }

    function maxTvl(
        int24 leftTick,
        int24 rightTick,
        int24 currentTick,
        int24 deviatedTick,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(currentTick),
            TickMath.getSqrtRatioAtTick(leftTick),
            TickMath.getSqrtRatioAtTick(rightTick),
            liquidity
        );
        {
            (uint256 tmp0, uint256 tmp1) = LiquidityAmounts.getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(deviatedTick),
                TickMath.getSqrtRatioAtTick(leftTick),
                TickMath.getSqrtRatioAtTick(rightTick),
                liquidity
            );
            if (tmp0 > amount0) {
                amount0 = tmp0;
            }
            if (tmp1 > amount1) {
                amount1 = tmp1;
            }
        }
    }

    function getMaxCapital(
        int24 leftLowerTick,
        int24 leftUpperTick,
        int24 rightLowerTick,
        int24 rightUpperTick,
        int24 currentTick,
        int24 deviatedTick,
        uint128 liquidity
    ) internal pure returns (uint256 capital) {
        (uint256 amount0, uint256 amount1) = maxTvl(leftLowerTick, leftUpperTick, currentTick, deviatedTick, liquidity);
        {
            (uint256 tmp0, uint256 tmp1) = maxTvl(rightLowerTick, rightUpperTick, currentTick, deviatedTick, liquidity);
            amount0 += tmp0;
            amount1 += tmp1;
        }
        return getCapital(amount0, amount1, currentTick);
    }

    function tvl(
        int24 leftTick,
        int24 rightTick,
        int24 currentTick,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(currentTick),
            TickMath.getSqrtRatioAtTick(leftTick),
            TickMath.getSqrtRatioAtTick(rightTick),
            liquidity
        );
    }

    function getErc20Capital(
        int24 leftLowerTick,
        int24 leftUpperTick,
        int24 rightLowerTick,
        int24 rightUpperTick,
        int24 currentTick,
        uint128 liquidity
    ) internal pure returns (uint256 capital) {
        (uint256 amount0, uint256 amount1) = tvl(leftLowerTick, leftUpperTick, currentTick, liquidity);
        {
            (uint256 tmp0, uint256 tmp1) = tvl(rightLowerTick, rightUpperTick, currentTick, liquidity);
            amount0 += tmp0;
            amount1 += tmp1;
        }
        capital = getCapital(amount0, amount1, currentTick);
        capital = FullMath.mulDiv(capital, 10**18 / 20, 10**18);
    }

    function execute(int24 positionWidth, int24 deviation) internal view returns (uint256 maxDeviationD18) {
        int24 leftLowerTick = 0;
        int24 leftUpperTick = positionWidth;
        int24 rightLowerTick = positionWidth / 2;
        int24 rightUpperTick = rightLowerTick + positionWidth;

        uint128 liquidity = 10**18;

        for (int24 currentTick = leftLowerTick; currentTick <= rightUpperTick; ++currentTick) {
            int24 deviatedTick = currentTick + deviation;
            uint256 minCapital = getMinCapital(
                leftLowerTick,
                leftUpperTick,
                rightLowerTick,
                rightUpperTick,
                currentTick,
                deviatedTick,
                liquidity
            );
            uint256 maxCapital = getMaxCapital(
                leftLowerTick,
                leftUpperTick,
                rightLowerTick,
                rightUpperTick,
                currentTick,
                deviatedTick,
                liquidity
            );
            uint256 erc20Capital = getErc20Capital(
                leftLowerTick,
                leftUpperTick,
                rightLowerTick,
                rightUpperTick,
                currentTick,
                liquidity
            );
            minCapital += erc20Capital;
            maxCapital += erc20Capital;
            uint256 capitalDeviationD18 = 10**22;
            if (minCapital != 0) {
                capitalDeviationD18 = FullMath.mulDiv(maxCapital, 10**18, minCapital);
            }
            if (capitalDeviationD18 > maxDeviationD18) {
                maxDeviationD18 = capitalDeviationD18;
            }
        }
    }

    function test() public {
        for (int24 positionWidth = 80; positionWidth <= 140; positionWidth += 20) {
            for (int24 deviation = 1; deviation <= 5; deviation += 1) {
                uint256 deviation0 = execute(positionWidth, deviation);
                uint256 deviation1 = execute(positionWidth, -deviation);
                if (deviation0 < deviation1) {
                    deviation0 = deviation1;
                }
                console2.log("Deviation: ");
                console2.log(uint24(positionWidth));
                console2.log(uint24(deviation));
                console2.log(deviation0);
            }
        }
    }
}
