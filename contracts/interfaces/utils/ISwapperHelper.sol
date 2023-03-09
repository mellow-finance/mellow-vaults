// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface ISwapperHelper {
    function swap(address from, address to, uint256 amountIn, uint256 minAmountOut) external;
}
