// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
pragma abicoder v2;

import "../interfaces/external/univ3/ISwapRouter.sol";

contract MockSwapRouter is ISwapRouter {
    struct ExactInputSingleArgs {
        uint256 amountOut;
    }

    ExactInputSingleArgs private exactInputSingleArgs;

    function setExactInputSingleArgs(uint256 amountOut_) external {
        exactInputSingleArgs.amountOut = amountOut_;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        amountOut = 0;
        emit ExactInputSingle(params.amountIn);
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut) {}

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn) {}

    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn) {}

    event ExactInputSingle(uint256 amountIn);
}
