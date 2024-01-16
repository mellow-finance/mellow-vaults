// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/external/univ3/IQuoter.sol";

contract MultiPathUniswapRouter {
    using SafeERC20 for IERC20;

    ISwapRouter public immutable router;
    IQuoterV2 public immutable quoter;

    constructor(ISwapRouter router_, IQuoterV2 quoter_) {
        router = router_;
        quoter = quoter_;
    }

    function quote(bytes[] memory paths, uint256[] memory amountsIn) external returns (uint256 totalAmountOut) {
        for (uint256 i = 0; i < paths.length; i++) {
            (uint256 amountOut, , , ) = quoter.quoteExactInput(paths[i], amountsIn[i]);
            totalAmountOut += amountOut;
        }
    }

    function swap(
        address tokenIn,
        bytes[] memory paths,
        uint256[] memory amountsIn,
        uint256[] memory amountOutMins
    ) external returns (uint256 amountOut) {
        uint256 amountIn = 0;
        for (uint256 i = 0; i < amountsIn.length; i++) amountIn += amountsIn[i];
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeIncreaseAllowance(address(router), amountIn);
        for (uint256 i = 0; i < paths.length; i++) {
            amountOut += router.exactInput(
                ISwapRouter.ExactInputParams({
                    path: paths[i],
                    amountIn: amountsIn[i],
                    recipient: msg.sender,
                    deadline: type(uint256).max,
                    amountOutMinimum: amountOutMins[i]
                })
            );
        }
        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        if (balance > 0) {
            IERC20(tokenIn).safeTransfer(msg.sender, balance);
        }
    }
}
