// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface ITrader {
    /// @notice Swap exact amount of input tokens for output tokens
    /// @param traderId Trader ID (used only by Chief trader)
    /// @param recipient Address of the recipient (not used by Chief trader)
    /// @param token0 Address of the token to be sold
    /// @param token1 Address of the token to be bought
    /// @param amount Amount of the input tokens to spend
    /// @param options Protocol-speceific options
    /// @return amountOut Amount of the output tokens received
    function swapExactInput(
        uint256 traderId,
        address recipient,
        address token0,
        address token1,
        uint256 amount,
        bytes memory options
    ) external returns (uint256 amountOut);

    /// @notice Swap input tokens for exact amount of output tokens
    /// @param traderId Trader ID (used only by Chief trader)
    /// @param recipient Address of the recipient (not used by Chief trader)
    /// @param token0 Address of the token to be sold
    /// @param token1 Address of the token to be bought
    /// @param amount Amount of the output tokens to receive
    /// @param options Protocol-speceific options
    /// @return amountIn of the input tokens spent
    function swapExactOutput(
        uint256 traderId,
        address recipient,
        address token0,
        address token1,
        uint256 amount,
        bytes memory options
    ) external returns (uint256 amountIn);
}
