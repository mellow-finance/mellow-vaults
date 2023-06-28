// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockRouter {
    using SafeERC20 for IERC20;

    uint256 public priceX96;

    function setPrice(uint256 priceX96_) external {
        priceX96 = priceX96_;
    }
    
    function swap(uint256 amountIn, address tokenIn, address tokenOut, address reciever) external {
        uint256 amountOut = amountIn * priceX96 / 2 ** 96;
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(reciever, amountOut);
    }
}