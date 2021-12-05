// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "./external/FullMath.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "./CommonLibrary.sol";
import "./external/TickMath.sol";

/// @notice Strategy shared utilities
library StrategyLibrary {
    function getUniV3Averages(IUniswapV3Pool pool, uint256 minTimespan)
        internal
        view
        returns (
            uint256 sqrtPriceX96,
            uint256 liquidity,
            uint32 timespan
        )
    {
        (, , uint16 observationIndex, uint16 observationCardinality, , , ) = pool.slot0();
        uint256 index = getUniV3ObservationIndex(pool, minTimespan, observationIndex, observationCardinality);
        (uint32 blockTimestampLast, int56 tickCumulativeLast, uint160 secondsPerLiquidityCumulativeX128Last, ) = pool
            .observations(index);
        (
            uint32 blockTimestampCurrent,
            int56 tickCumulativeCurrent,
            uint160 secondsPerLiquidityCumulativeX128Current,

        ) = pool.observations(observationIndex);
        timespan = blockTimestampCurrent - blockTimestampLast;
        int256 tickAverage = (int256(tickCumulativeCurrent) - int256(tickCumulativeLast)) / int256(uint256(timespan));
        sqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24(tickAverage));

        uint160 avgSecondsPerLiquidityX128 = (secondsPerLiquidityCumulativeX128Current -
            secondsPerLiquidityCumulativeX128Last) / timespan;
        liquidity = CommonLibrary.Q128 / avgSecondsPerLiquidityX128;
    }

    function getUniV3ObservationIndex(
        IUniswapV3Pool pool,
        uint256 minTimespan,
        uint16 observationIndex,
        uint16 observationCardinality
    ) internal view returns (uint256) {
        uint256 left = 0;
        uint256 right = observationCardinality;
        (uint256 current, , , ) = pool.observations(observationIndex);
        while (right - left > 1) {
            uint256 middle = (left + right) / 2;
            // an array [observationIndex + 1, ..., observationIndex + observationCardinality] is sorted desc by timespan
            uint256 midIdx = (uint256(observationIndex + 1) + middle) % observationCardinality;
            (uint32 blockTimestamp, , , ) = pool.observations(midIdx);
            uint256 timespan = current - blockTimestamp;
            if (timespan >= minTimespan) {
                // timespan >= minTimespan is ok for result so we assign it to left element
                left = middle;
            } else {
                // timespan < minTimespan is not ok, so we assign it to right (which is exclusive)
                right = middle;
            }
        }
        return (uint256(observationIndex + 1) + left) % observationCardinality;
    }

    /// See https://www.notion.so/mellowprotocol/Swap-w-o-slippage-aa13edef527145deb3a0a8d705ed3701
    function swapToTargetWithoutSlippage(
        uint256 targetRatioX96,
        uint256 sqrtPriceX96,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 fee
    ) internal pure returns (uint256 tokenIn, bool zeroForOne) {
        uint256 rx = FullMath.mulDiv(targetRatioX96, token0Amount, CommonLibrary.Q96);
        uint256 pX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, CommonLibrary.Q96);
        zeroForOne = rx > token1Amount;
        if (zeroForOne) {
            uint256 numerator = rx - token1Amount;
            uint256 denominatorX96 = targetRatioX96 +
                FullMath.mulDiv(pX96, CommonLibrary.UNI_FEE_DENOMINATOR, CommonLibrary.UNI_FEE_DENOMINATOR - fee);
            tokenIn = FullMath.mulDiv(numerator, CommonLibrary.Q96, denominatorX96);
        } else {
            uint256 numeratorX96 = FullMath.mulDiv(rx - token1Amount, pX96, 1);
            uint256 denominatorX96 = pX96 +
                FullMath.mulDiv(
                    targetRatioX96,
                    CommonLibrary.UNI_FEE_DENOMINATOR,
                    CommonLibrary.UNI_FEE_DENOMINATOR - fee
                );
            tokenIn = FullMath.mulDiv(numeratorX96, 1, denominatorX96);
        }
    }

    // https://www.notion.so/mellowprotocol/Swap-With-Slippage-calculation-f7a89a76b6094287a8d3c6f5068527bd
    function swapToTargetWithSlippage(
        uint256 targetRatioX96,
        uint256 sqrtPriceX96,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 fee,
        uint256 liquidity
    ) internal pure returns (uint256 tokenIn, bool zeroForOne) {
        zeroForOne = FullMath.mulDiv(token0Amount, targetRatioX96, token1Amount) > CommonLibrary.Q96;

        uint256 l = liquidity;
        uint256 lHat = (liquidity / (CommonLibrary.UNI_FEE_DENOMINATOR - fee)) * CommonLibrary.UNI_FEE_DENOMINATOR;
        if (zeroForOne) {
            (l, lHat) = (lHat, l);
        }
        uint256 cX96 = FullMath.mulDiv(targetRatioX96, l, lHat);
        uint256 b1X96 = FullMath.mulDiv(cX96, CommonLibrary.Q96, sqrtPriceX96);
        uint256 b2X96 = FullMath.mulDiv(targetRatioX96, token0Amount, lHat);
        uint256 b3X96 = FullMath.mulDiv(CommonLibrary.Q96, token1Amount, lHat);
        uint256 b4X96 = sqrtPriceX96;
        uint256 bX96;
        if (b1X96 + b2X96 > b3X96 + b4X96) {
            bX96 = b1X96 + b2X96 - b3X96 - b4X96;
        } else {
            bX96 = b3X96 + b4X96 - b1X96 - b2X96;
        }
        bX96 = bX96 / 2;
        uint256 d = FullMath.mulDiv(bX96, bX96, CommonLibrary.Q96) + cX96;
        uint256 sqrtPX96 = CommonLibrary.sqrtX96(d) - bX96;
        if (zeroForOne) {
            uint256 priceProductX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPX96, CommonLibrary.Q96);
            tokenIn = FullMath.mulDiv(l, sqrtPX96 - sqrtPriceX96, priceProductX96);
        } else {
            tokenIn = FullMath.mulDiv(lHat, sqrtPriceX96 - sqrtPX96, CommonLibrary.Q96);
        }
    }
}
