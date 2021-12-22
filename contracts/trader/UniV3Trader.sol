// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/external/univ3/ISwapRouter.sol";
import "./interfaces/IUniV3Trader.sol";
import "./libraries/TraderExceptionsLibrary.sol";
import "./Trader.sol";

/// @notice Contract that can execute ERC20 swaps on Uniswap V3
contract UniV3Trader is Trader, IUniV3Trader {
    using SafeERC20 for IERC20;

    ISwapRouter public immutable swapRouter;

    constructor(address _swapRouter) {
        require(_swapRouter != address(0), TraderExceptionsLibrary.ADDRESS_ZERO_EXCEPTION);
        swapRouter = ISwapRouter(_swapRouter);
    }

    /// @inheritdoc ITrader
    function swapExactInput(
        uint256,
        address recipient,
        address token0,
        address token1,
        uint256 amount,
        bytes memory options
    ) external returns (uint256 amountOut) {
        Options memory options_ = abi.decode(options, (Options));
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: token0,
            tokenOut: token1,
            fee: options_.fee,
            recipient: recipient,
            deadline: options_.deadline,
            amountIn: amount,
            amountOutMinimum: options_.limitAmount,
            sqrtPriceLimitX96: options_.sqrtPriceLimitX96
        });
        IERC20(token0).safeTransferFrom(recipient, address(this), amount);
        _approveERC20TokenIfNecessary(token0, address(swapRouter));
        amountOut = swapRouter.exactInputSingle(params);
    }

    /// @inheritdoc ITrader
    function swapExactOutput(
        uint256,
        address recipient,
        address token0,
        address token1,
        uint256 amount,
        bytes memory options
    ) external returns (uint256 amountIn) {
        Options memory options_ = abi.decode(options, (Options));
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: token0,
            tokenOut: token1,
            fee: options_.fee,
            recipient: recipient,
            deadline: options_.deadline,
            amountOut: amount,
            amountInMaximum: options_.limitAmount,
            sqrtPriceLimitX96: options_.sqrtPriceLimitX96
        });
        IERC20(token0).safeTransferFrom(recipient, address(this), options_.limitAmount);
        _approveERC20TokenIfNecessary(token0, address(swapRouter));
        amountIn = swapRouter.exactOutputSingle(params);
        if (amountIn < options_.limitAmount) {
            uint256 change;
            unchecked {
                change = options_.limitAmount - amountIn;
            }
            IERC20(token0).safeTransfer(recipient, change);
        }
    }
}
