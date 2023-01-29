// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

contract MockAggregator {
    uint256 public currentPrice = 1 << 96;

    function updatePrice(uint256 newPrice) public {
        currentPrice = newPrice;
    }

    function latestAnswer() public returns (int256) {
        return int256(currentPrice);
    }

}
