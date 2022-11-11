// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../strategies/HStrategyV2.sol";

contract MockHStrategyV2 is HStrategyV2 {
    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_)
        HStrategyV2(positionManager_, router_)
    {}

    function positionRebalance() external {
        _positionRebalance();
    }

    function swapRebalance() external {
        _swapRebalance();
    }

    function liquidityRebalance() external {
        _liquidityRebalance();
    }
}
