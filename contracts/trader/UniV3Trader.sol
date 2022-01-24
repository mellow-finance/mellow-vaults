// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/trader/IUniV3Trader.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./Trader.sol";

/// @notice Contract that can execute ERC20 swaps on Uniswap V3
contract UniV3Trader is Trader, IUniV3Trader {
    using SafeERC20 for IERC20;

    ISwapRouter public immutable swapRouter;

    constructor(address _swapRouter) {
        swapRouter = ISwapRouter(_swapRouter);
    }

    /// @inheritdoc ITrader
    function swapExactInput(
        uint256,
        uint256 amount,
        address recipient,
        PathItem[] memory path,
        bytes memory options
    ) external returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        require(super._validatePathLinked(path), ExceptionsLibrary.INVALID_VALUE);
        Options memory options_ = abi.decode(options, (Options));
        if (path.length == 1) return _swapExactInputSingle(path[0].token0, path[0].token1, amount, recipient, options_);
        else return _swapExactInputMultihop(amount, recipient, path, options_);
    }

    /// @inheritdoc ITrader
    function swapExactOutput(
        uint256,
        uint256 amount,
        address recipient,
        PathItem[] memory path,
        bytes memory options
    ) external returns (uint256) {
        require(super._validatePathLinked(path), ExceptionsLibrary.INVALID_VALUE);
        Options memory options_ = abi.decode(options, (Options));
        if (path.length == 1)
            return _swapExactOutputSingle(path[0].token0, path[0].token1, amount, recipient, options_);
        else return _swapExactOutputMultihop(amount, recipient, path, options_);
    }

    function _swapExactInputSingle(
        address input,
        address output,
        uint256 amount,
        address recipient,
        Options memory options
    ) internal returns (uint256 amountOut) {
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
        IERC20(input).safeTransferFrom(recipient, address(this), amount);
        _increaseAllowancesByAmount(input, address(swapRouter), amount);
        amountOut = swapRouter.exactInputSingle(params);
        _decreaseAllowances(input, address(swapRouter));
    }

    function _swapExactOutputSingle(
        address input,
        address output,
        uint256 amount,
        address recipient,
        Options memory options
    ) internal returns (uint256 amountIn) {
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
        IERC20(input).safeTransferFrom(recipient, address(this), options.limitAmount);
        _increaseAllowancesByAmount(input, address(swapRouter), amount);
        amountIn = swapRouter.exactOutputSingle(params);
        if (amountIn < options.limitAmount) IERC20(input).safeTransfer(recipient, options.limitAmount - amountIn);
        _decreaseAllowances(input, address(swapRouter));
    }

    function _swapExactInputMultihop(
        uint256 amount,
        address recipient,
        PathItem[] memory path,
        Options memory options
    ) internal returns (uint256 amountOut) {
        address input = path[0].token0;
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: _makeMultihopPath(path),
            recipient: recipient,
            deadline: options.deadline,
            amountIn: amount,
            amountOutMinimum: options.limitAmount
        });
        IERC20(input).safeTransferFrom(recipient, address(this), amount);
        _increaseAllowancesByAmount(input, address(swapRouter), amount);
        amountOut = swapRouter.exactInput(params);
        _decreaseAllowances(input, address(swapRouter));
    }

    function _swapExactOutputMultihop(
        uint256 amount,
        address recipient,
        PathItem[] memory path,
        Options memory options
    ) internal returns (uint256 amountIn) {
        address input = path[0].token0;
        ISwapRouter.ExactOutputParams memory params = ISwapRouter.ExactOutputParams({
            path: _reverseBytes(_makeMultihopPath(path)),
            recipient: recipient,
            deadline: options.deadline,
            amountOut: amount,
            amountInMaximum: options.limitAmount
        });
        IERC20(input).safeTransferFrom(recipient, address(this), options.limitAmount);
        _increaseAllowancesByAmount(input, address(swapRouter), amount);
        amountIn = swapRouter.exactOutput(params);
        if (amountIn < options.limitAmount) IERC20(input).safeTransfer(recipient, options.limitAmount - amountIn);
        _decreaseAllowances(input, address(swapRouter));
    }

    function _reverseBytes(bytes memory input) internal pure returns (bytes memory output) {
        for (uint256 i = 0; i < input.length; ++i) output[i] = input[input.length - 1 - i];
    }

    function _makeMultihopPath(PathItem[] memory path) internal pure returns (bytes memory) {
        bytes memory result;
        for (uint256 i = 0; i < path.length; ++i) {
            PathItemOptions memory pathItemOptions = abi.decode(path[i].options, (PathItemOptions));
            result = bytes.concat(result, abi.encodePacked(path[i].token0, abi.encodePacked(pathItemOptions.fee)));
        }
        result = bytes.concat(result, abi.encodePacked(path[path.length - 1].token1));
        return result;
    }
}
