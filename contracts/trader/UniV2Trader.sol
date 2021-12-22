// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniV2Trader.sol";
import "./libraries/TraderExceptionsLibrary.sol";
import "./Trader.sol";

/// @notice Contract that executes swaps on Uniswap V2
contract UniV2Trader is Trader, IUniV2Trader {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public immutable router;

    constructor(address _router) {
        require(_router != address(0), TraderExceptionsLibrary.ADDRESS_ZERO_EXCEPTION);
        router = IUniswapV2Router02(_router);
    }

    /// @inheritdoc ITrader
    function swapExactInput(
        uint256,
        address recipient,
        address token0,
        address token1,
        uint256 amount,
        bytes calldata options
    ) external returns (uint256) {
        Options memory options_ = abi.decode(options, (Options));
        IERC20(token0).safeTransferFrom(recipient, address(this), amount);
        _approveERC20TokenIfNecessary(token0, address(router));
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amount,
            options_.limitAmount,
            _makePath(token0, token1),
            recipient,
            options_.deadline
        );
        return amounts[1];
    }

    /// @inheritdoc ITrader
    function swapExactOutput(
        uint256,
        address recipient,
        address token0,
        address token1,
        uint256 amount,
        bytes calldata options
    ) external returns (uint256) {
        Options memory options_ = abi.decode(options, (Options));
        IERC20(token0).safeTransferFrom(recipient, address(this), options_.limitAmount);
        uint256[] memory amounts = router.swapTokensForExactTokens(
            amount,
            options_.limitAmount,
            _makePath(token0, token1),
            recipient,
            options_.deadline
        );
        if (amounts[0] < options_.limitAmount) {
            uint256 change;
            unchecked {
                change = options_.limitAmount - amounts[0];
            }
            IERC20(token0).safeTransfer(recipient, change);
        }
        return amounts[0];
    }

    function _makePath(address token0, address token1) internal pure returns (address[] memory result) {
        result = new address[](2);
        result[0] = token0;
        result[1] = token1;
    }
}
