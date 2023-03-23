// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

interface ISwapper {
    function swap(address token0, address token1, uint256 amountIn, uint256 minAmountOut, bytes memory data) external returns (uint256);
}
