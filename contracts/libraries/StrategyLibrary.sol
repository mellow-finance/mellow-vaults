// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./external/FullMath.sol";
import "./CommonLibrary.sol";

/// @notice Strategy shared utilities
library StrategyLibrary {
    function swapToTarget(
        uint256 targetRatioX96,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 fee
    ) internal pure returns (uint256 tokenIn, bool zeroForOne) {
        zeroForOne = FullMath.mulDiv(token0Amount, targetRatioX96, token1Amount) > CommonLibrary.Q96;
    }

    /// See https://www.notion.so/mellowprotocol/Swap-calculation-f7a89a76b6094287a8d3c6f5068527bd
    function swapToTargetWithSlippage(
        uint256 targetRatioX96,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 fee,
        uint256 liquidity,
        uint256 sqrtPriceX96
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
