// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockRouter is Test {

    using SafeERC20 for IERC20;

    function add(address token, address account, uint256 amount) public {
        uint256 balance = IERC20(token).balanceOf(account);
        deal(token, account, balance + amount);
    }

    function sub(address token, address account, uint256 amount) public {
        uint256 balance = IERC20(token).balanceOf(account);
        deal(token, account, balance - amount);
    }

    function swap(address token0, address token1, uint256 amountIn, uint256 amountOut) public {
        sub(token0, msg.sender, amountIn);
        add(token1, msg.sender, amountOut);
    }
}
