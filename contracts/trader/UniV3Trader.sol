// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./libraries/ExceptionsLibrary.sol";
import "./Trader.sol";

contract UniV3Trader is Trader, ITrader {
    struct UnderlyingProtocolOptions {
        ISwapRouter swapRouter;
    }

    struct Options {
        uint24 fee;
        uint160 sqrtPriceLimitX96;
        uint256 deadline;
        uint256 limitAmount;
    }

    struct PathItemOptions {
        uint24 fee;
    }

    UnderlyingProtocolOptions public underlyingProtocolOptions;

    constructor(address _chiefTrader, bytes memory _underlyingProtocolOptions) {
        chiefTrader = _chiefTrader;
        underlyingProtocolOptions = abi.decode(_underlyingProtocolOptions, (UnderlyingProtocolOptions));
    }

    function swapExactInput(
        uint256,
        address input,
        address output,
        uint256 amount,
        address recipient,
        PathItem[] calldata path,
        bytes calldata options
    ) external returns (uint256 outputAmount) {
        Options memory options_ = abi.decode(options, (Options));
        if (path.length == 0) {
            return _swapExactInputSingle(input, output, amount, recipient, options_);
        } else {
            require(_validatePathLinked(input, output, path), ExceptionsLibrary.INVALID_TRADE_PATH_EXCEPTION);
            // TODO: implement multihop swap
        }
    }

    function swapExactOutput(
        uint256,
        address input,
        address output,
        uint256 amount,
        address recipient,
        PathItem[] calldata path,
        bytes calldata options
    ) external returns (uint256 outputAmount) {
        Options memory options_ = abi.decode(options, (Options));
        if (path.length == 0) {
            return _swapExactOutputSingle(input, output, amount, recipient, options_);
        } else {
            require(_validatePathLinked(input, output, path), ExceptionsLibrary.INVALID_TRADE_PATH_EXCEPTION);
            // TODO: implement multihop swap
        }
    }

    function _validatePathLinked(
        address input,
        address output,
        PathItem[] calldata path
    ) internal pure returns (bool result) {
        for (uint256 i = 0; i < path.length; i++) {
            if (i == 0 && path[0].token0 != input) {
                return false;
            } else if (i == path.length - 1 && path[i].token1 != output) {
                return false;
            } else {
                if (path[i].token0 != path[i - 1].token1 || path[i].token1 != path[i + 1].token0) {
                    return false;
                }
            }
        }
        return true;
    }

    function _swapExactInputSingle(
        address input,
        address output,
        uint256 amount,
        address recipient,
        Options memory options
    ) internal returns (uint256 amountOut) {
        _requireChiefTrader();
        ISwapRouter swapRouter = underlyingProtocolOptions.swapRouter;
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: input,
            tokenOut: output,
            fee: options.fee,
            recipient: recipient,
            deadline: options.deadline,
            amountIn: amount,
            amountOutMinimum: options.limitAmount,
            sqrtPriceLimitX96: options.sqrtPriceLimitX96
        });
        TransferHelper.safeTransferFrom(input, msg.sender, address(this), amount);
        _safeApproveERC20TokenIfNecessary(input, address(swapRouter));
        amountOut = swapRouter.exactInputSingle(params);
    }

    function _swapExactOutputSingle(
        address input,
        address output,
        uint256 amount,
        address recipient,
        Options memory options
    ) internal returns (uint256 amountIn) {
        _requireChiefTrader();
        ISwapRouter swapRouter = underlyingProtocolOptions.swapRouter;
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: input,
            tokenOut: output,
            fee: options.fee,
            recipient: recipient,
            deadline: options.deadline,
            amountOut: amount,
            amountInMaximum: options.limitAmount,
            sqrtPriceLimitX96: options.sqrtPriceLimitX96
        });
        TransferHelper.safeTransferFrom(input, msg.sender, address(this), amount);
        _safeApproveERC20TokenIfNecessary(input, address(swapRouter));
        amountIn = swapRouter.exactOutputSingle(params);
    }
}
