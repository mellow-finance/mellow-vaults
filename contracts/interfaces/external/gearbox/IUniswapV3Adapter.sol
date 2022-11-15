// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.9;

import { IAdapter } from "./helpers/IAdapter.sol";
import { ISwapRouter } from "./helpers/uniswap/IUniswapV3.sol";

interface IUniswapV3AdapterExceptions {
    error IncorrectPathLengthException();
}

interface IUniswapV3Adapter is
    IAdapter,
    ISwapRouter,
    IUniswapV3AdapterExceptions
{
    /// @dev A struct encoding parameters for exactAllInputSingle,
    ///      which is unique to the Gearbox adapter
    /// @param tokenIn Token that is spent by the swap
    /// @param tokenOut Token that is received from the swap
    /// @param fee The fee category to use
    /// @param deadline The timestamp, after which the swap will revert
    /// @param rateMinRAY The minimal exhange rate between tokenIn and tokenOut
    ///                   used to calculate amountOutMin on the spot, since the input amount
    ///                   may not always be known in advance
    /// @param sqrtPriceLimitX96 The max execution price. Will be ignored if set to 0.
    struct ExactAllInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 deadline;
        uint256 rateMinRAY;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Sends an order to swap the entire balance of one token for as much as possible of another token
    /// - Fills the `ExactInputSingleParams` struct
    /// - Makes a max allowance fast check call, passing the new struct as params
    /// @param params The parameters necessary for the swap, encoded as `ExactAllInputSingleParams` in calldata
    function exactAllInputSingle(ExactAllInputSingleParams calldata params)
        external
        returns (uint256 amountOut);

    /// @dev A struct encoding parameters for exactAllInput,
    ///      which is unique to the Gearbox adapter
    /// @param path Bytes array encoding the sequence of swaps to perform,
    ///             in the format TOKEN_FEE_TOKEN_FEE_TOKEN...
    /// @param deadline The timestamp, after which the swap will revert
    /// @param rateMinRAY The minimal exhange rate between tokenIn and tokenOut
    ///                   used to calculate amountOutMin on the spot, since the input amount
    ///                   may not always be known in advance
    struct ExactAllInputParams {
        bytes path;
        uint256 deadline;
        uint256 rateMinRAY;
    }

    /// @notice Swaps the entire balance of one token for as much as possible of another along the specified path
    /// - Fills the `ExactAllInputParams` struct
    /// - Makes a max allowance fast check call, passing the new struct as `params`
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactAllInputParams` in calldata
    function exactAllInput(ExactAllInputParams calldata params)
        external
        returns (uint256 amountOut);
}