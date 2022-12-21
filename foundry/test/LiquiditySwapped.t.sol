// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "../lib/forge-std/src/console2.sol";
import "./helpers/libraries/LiquidityAmounts.sol";
import "./helpers/libraries/TickMath.sol";
import "./helpers/libraries/FullMath.sol";

contract LiquiditySwapped {
    function targetUniV3LiquidityRatio(
        int24 targetTick_,
        int24 tickLower,
        int24 tickUpper
    ) public view returns (uint128 liquidityRatioD, bool isNegative) {
        uint128 DENOMINATOR = 10**18;
        int24 midTick = (tickUpper + tickLower) / 2;
        isNegative = midTick > targetTick_;
        if (isNegative) {
            liquidityRatioD = uint128(uint24(midTick - targetTick_));
        } else {
            liquidityRatioD = uint128(uint24(targetTick_ - midTick));
        }
        liquidityRatioD = uint128(liquidityRatioD * DENOMINATOR) / uint128(uint24(tickUpper - tickLower) / 2);
    }

    function getAmounts(
        int24 tick,
        int24 leftLowerTick,
        int24 leftUpperTick,
        int24 rightLowerTick,
        int24 rightUpperTick
    ) public view returns (uint256 amount0, uint256 amount1) {
        (uint128 liquidityRatio, ) = targetUniV3LiquidityRatio(tick, leftLowerTick, leftUpperTick);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(tick),
            TickMath.getSqrtRatioAtTick(leftLowerTick),
            TickMath.getSqrtRatioAtTick(leftUpperTick),
            liquidityRatio
        );
        {
            (uint256 tmp0, uint256 tmp1) = LiquidityAmounts.getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(tick),
                TickMath.getSqrtRatioAtTick(rightLowerTick),
                TickMath.getSqrtRatioAtTick(rightUpperTick),
                10**18 - liquidityRatio
            );
            amount0 += tmp0;
            amount1 += tmp1;
        }
    }

    function execute(int24 positionWidth, int24 deviation) internal view returns (uint256 maxRatioD18) {
        int24 leftLowerTick = 0;
        int24 leftUpperTick = positionWidth;
        int24 rightLowerTick = positionWidth / 2;
        int24 rightUpperTick = rightLowerTick + positionWidth;

        uint128 totalLiquidity = 10**18;

        for (int24 currentTick = rightLowerTick; currentTick + deviation <= leftUpperTick; ++currentTick) {
            int24 deviatedTick = currentTick + deviation;
            (uint128 initialRatio, ) = targetUniV3LiquidityRatio(currentTick, leftLowerTick, leftUpperTick);
            (uint256 amount0, uint256 amount1) = getAmounts(
                currentTick,
                leftLowerTick,
                leftUpperTick,
                rightLowerTick,
                rightUpperTick
            );

            (uint256 tmp0, uint256 tmp1) = getAmounts(
                deviatedTick,
                leftLowerTick,
                leftUpperTick,
                rightLowerTick,
                rightUpperTick
            );
            uint256 priceX96 = FullMath.mulDiv(
                TickMath.getSqrtRatioAtTick(deviatedTick),
                TickMath.getSqrtRatioAtTick(deviatedTick),
                2**96
            );
            uint256 totalCapital = FullMath.mulDiv(amount0, priceX96, 2**96) + amount1;
            if (amount0 > tmp0) {
                uint256 swappedCapital = FullMath.mulDiv(amount0 - tmp0, priceX96, 2**96);
                if (FullMath.mulDiv(swappedCapital, 10**18, totalCapital) > maxRatioD18) {
                    maxRatioD18 = FullMath.mulDiv(swappedCapital, 10**18, totalCapital);
                }
            } else {
                uint256 swappedCapital = amount1 - tmp1;
                if (FullMath.mulDiv(swappedCapital, 10**18, totalCapital) > maxRatioD18) {
                    maxRatioD18 = FullMath.mulDiv(swappedCapital, 10**18, totalCapital);
                }
            }
        }
    }

    function test() public {
        for (int24 positionWidth = 80; positionWidth <= 400; positionWidth += 20) {
            for (int24 deviation = 5; deviation <= 60; deviation += 5) {
                uint256 swappedCapitalD18 = execute(positionWidth, deviation);
                console2.log("SWAP: ");
                console2.log(uint24(positionWidth));
                console2.log(uint24(deviation));
                console2.log(swappedCapitalD18);
            }
        }
    }
}
