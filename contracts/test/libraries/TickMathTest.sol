// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../../libraries/external/TickMath.sol";

contract TickMathTest {
    function getSqrtRatioAtTick(int24 tick) external pure returns (uint160 sqrtPriceX96) {
        return TickMath.getSqrtRatioAtTick(tick);
    }

    function getTickAtSqrtRatio(uint160 sqrtPriceX96) external pure returns (int24 tick) {
        return TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }
<<<<<<< HEAD
}
=======
}
>>>>>>> main
