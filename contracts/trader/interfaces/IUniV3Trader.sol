// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ITrader.sol";

interface IUniV3Trader is ITrader {
    struct Options {
        uint24 fee;
        uint160 sqrtPriceLimitX96;
        uint256 deadline;
        uint256 limitAmount;
    }
}
