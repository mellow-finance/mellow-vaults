// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ITrader.sol";

interface IUniV2Trader is ITrader {
    struct Options {
        uint256 deadline;
        uint256 limitAmount;
    }
}
