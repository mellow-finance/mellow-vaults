// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IMock1InchRouter {
    function swap(
        address from,
        address to,
        uint256 amountIn,
        uint256 exepctedAmountOut
    ) external;
}

contract Mock1InchRouter is IMock1InchRouter {
    using SafeERC20 for IERC20;

    function swap(
        address from,
        address to,
        uint256 amountIn,
        uint256 expectedAmountOut
    ) external override {
        IERC20(from).transferFrom(msg.sender, address(this), amountIn);
        IERC20(to).transfer(msg.sender, expectedAmountOut);
    }

    function getData(
        address from,
        address to,
        uint256 amountIn,
        uint256 exepctedAmountOut
    ) external pure returns (bytes memory) {
        return abi.encodeWithSelector(IMock1InchRouter.swap.selector, from, to, amountIn, exepctedAmountOut);
    }
}
