// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniV2Trader.sol";
import "./libraries/TraderExceptionsLibrary.sol";
import "./Trader.sol";

contract UniV2Trader is Trader, IUniV2Trader {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public router;

    constructor(address _router) {
        router = IUniswapV2Router02(_router);
    }

    /// @inheritdoc ITrader
    function swapExactInput(
        uint256,
        uint256 amount,
        address recipient,
        PathItem[] memory path,
        bytes calldata options
    ) external returns (uint256) {
        _validatePathLinked(path);
        Options memory options_ = abi.decode(options, (Options));
        IERC20(path[0].token0).safeTransferFrom(recipient, address(this), amount);
        _approveERC20TokenIfNecessary(path[0].token0, address(router));
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amount,
            options_.limitAmount,
            _makePath(path),
            recipient,
            options_.deadline
        );
        return amounts[amounts.length - 1];
    }

    /// @inheritdoc ITrader
    function swapExactOutput(
        uint256,
        uint256 amount,
        address recipient,
        PathItem[] memory path,
        bytes calldata options
    ) external returns (uint256) {
        _validatePathLinked(path);
        Options memory options_ = abi.decode(options, (Options));
        IERC20(path[0].token0).safeTransferFrom(recipient, address(this), options_.limitAmount);
        uint256[] memory amounts = router.swapTokensForExactTokens(
            amount,
            options_.limitAmount,
            _makePath(path),
            recipient,
            options_.deadline
        );
        if (amounts[0] < options_.limitAmount) {
            uint256 change;
            unchecked {
                change = options_.limitAmount - amounts[0];
            }
            IERC20(path[0].token0).safeTransfer(recipient, change);
        }
        return amounts[0];
    }

    function _makePath(PathItem[] memory path) internal pure returns (address[] memory result) {
        result = new address[](path.length + 1);
        result[0] = path[0].token0;
        for (uint256 i = 1; i < path.length; ++i) result[i + 1] = path[i].token1;
    }
}
