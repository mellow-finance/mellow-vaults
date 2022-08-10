// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../strategies/HStrategy.sol";

contract MockHStrategy is HStrategy {
    constructor(
        INonfungiblePositionManager positionManager_,
        ISwapRouter router_,
        address uniV3Helper_,
        address hStrategyHelper_
    ) HStrategy(positionManager_, router_, uniV3Helper_, hStrategyHelper_) {}

    function swapTokens(
        TokenAmounts memory expectedTokenAmounts,
        TokenAmounts memory currentTokenAmounts,
        RebalanceTokenAmounts memory restrictions
    ) external returns (int256[] memory swappedAmounts) {
        swappedAmounts = _swapTokens(currentTokenAmounts, expectedTokenAmounts, restrictions, erc20Vault, tokens);
    }
}
