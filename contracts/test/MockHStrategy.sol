// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../strategies/HStrategy.sol";

contract MockHStrategy is HStrategy {
    constructor(INonfungiblePositionManager positionManager_, ISwapRouter router_)
        HStrategy(positionManager_, router_)
    {}

    function swapTokens(
        TokenAmounts memory expectedTokenAmounts,
        TokenAmounts memory currentTokenAmounts,
        RebalanceRestrictions memory restrictions
    ) external returns (uint256[] memory swappedAmounts) {
        swappedAmounts = _swapTokens(expectedTokenAmounts, currentTokenAmounts, restrictions, erc20Vault, tokens);
    }
}
