// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// When trading from a smart contract, the most important thing to keep in mind is that
// access to an external price source is required. Without this, trades can be frontrun for considerable loss.

interface ITrader {
    /// @notice Link to the parent ITrader-compatible contract
    /// @return Address of the ITrader-compatible contract
    function chiefTrader() external returns (address);

    /// @notice Swap exact amount of input tokens for output tokens (single-path)
    /// @param input Address of the input token
    /// @param output Address of the output token
    /// @param amount Amount of the input tokens to spend
    /// @param options Protocol-speceific options
    /// @return amountOut Amount of the output tokens received
    function swapExactInputSingle(
        address input,
        address output,
        uint256 amount,
        address recipient,
        bytes calldata options
    ) external returns (uint256 amountOut);

    /// @notice Swap exact amount of input tokens for output tokens (single-path)
    /// @param input Address of the input token
    /// @param output Address of the output token
    /// @param amount Amount of the output tokens to receive
    /// @param options Protocol-speceific options
    /// @return amountIn of the input tokens spent
    function swapExactOutputSingle(
        address input,
        address output,
        uint256 amount,
        address recipient,
        bytes calldata options
    ) external returns (uint256 amountIn);

    /// @notice Swap exact amount of input tokens for output tokens (multiple-path)
    /// @param input Address of the input token
    /// @param output Address of the output token
    /// @param amount Amount of the input tokens to spend
    /// @param options Protocol-speceific options
    /// @return amountOut Amount of the output tokens received
    function swapExactInputMultihop(
        address input,
        address output,
        uint256 amount,
        address recipient,
        bytes calldata options
    ) external returns (uint256 amountOut);

    /// @notice Swap exact amount of input tokens for output tokens (multiple-path)
    /// @param input Address of the input token
    /// @param output Address of the output token
    /// @param amount Amount of the output tokens to receive
    /// @param options Protocol-speceific options
    /// @return amountIn of the input tokens spent
    function swapExactOutputMultihop(
        address input,
        address output,
        uint256 amount,
        address recipient,
        bytes calldata options
    ) external returns (uint256 amountIn);
}
