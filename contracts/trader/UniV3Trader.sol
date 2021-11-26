// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./interfaces/ITrader.sol";
import "./libraries/Exceptions.sol";
import "./Trader.sol";

contract UniV3Trader is ITrader, Trader, ERC165 {
    struct UnderlyingProtocolOptions {
        ISwapRouter swapRouter;
    }

    // @dev no need to define `In` and `Out` due to their symmetry
    struct SwapSingleOptions {
        uint24 fee;
        uint160 sqrtPriceLimitX96;
        uint256 deadline;
        uint256 limitAmount;
    }

    // @dev no need to define `In` and `Out` due to their symmetry
    struct SwapMultihopOptions {
        bytes path;
        uint256 deadline;
        uint256 limitAmount;
    }

    address public chiefTrader;
    UnderlyingProtocolOptions public underlyingProtocolOptions;

    constructor(address _chiefTrader, bytes memory _underlyingProtocolOptions) {
        chiefTrader = _chiefTrader;
        underlyingProtocolOptions = abi.decode(_underlyingProtocolOptions, (UnderlyingProtocolOptions));
    }

    function swapExactInputSingle(
        address input,
        address output,
        uint256 amount,
        address recipient,
        bytes calldata options
    ) external returns (uint256 amountOut) {
        _requireChiefTrader();
        SwapSingleOptions memory swapOptions = abi.decode(options, (SwapSingleOptions));
        ISwapRouter swapRouter = underlyingProtocolOptions.swapRouter;
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: input,
            tokenOut: output,
            fee: swapOptions.fee,
            recipient: recipient,
            deadline: swapOptions.deadline,
            amountIn: amount,
            amountOutMinimum: swapOptions.limitAmount,
            sqrtPriceLimitX96: swapOptions.sqrtPriceLimitX96
        });
        TransferHelper.safeTransferFrom(input, msg.sender, address(this), amount);
        _safeApproveERC20TokenIfNecessary(input, address(swapRouter));
        amountOut = swapRouter.exactInputSingle(params);
    }

    function swapExactOutputSingle(
        address input,
        address output,
        uint256 amount,
        address recipient,
        bytes calldata options
    ) external returns (uint256 amountIn) {
        _requireChiefTrader();
        SwapSingleOptions memory swapOptions = abi.decode(options, (SwapSingleOptions));
        ISwapRouter swapRouter = underlyingProtocolOptions.swapRouter;
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: input,
            tokenOut: output,
            fee: swapOptions.fee,
            recipient: recipient,
            deadline: swapOptions.deadline,
            amountOut: amount,
            amountInMaximum: swapOptions.limitAmount,
            sqrtPriceLimitX96: swapOptions.sqrtPriceLimitX96
        });
        TransferHelper.safeTransferFrom(input, msg.sender, address(this), amount);
        _safeApproveERC20TokenIfNecessary(input, address(swapRouter));
        amountIn = swapRouter.exactOutputSingle(params);
    }

    function swapExactInputMultihop(
        address input,
        address output,
        uint256 amount,
        address recipient,
        bytes calldata options
    ) external returns (uint256) {}

    function swapExactOutputMultihop(
        address input,
        address output,
        uint256 amount,
        address recipient,
        bytes calldata options
    ) external returns (uint256) {}

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return (interfaceId == this.supportsInterface.selector || interfaceId == type(ITrader).interfaceId);
    }

    // TODO: move to base class
    function _requireChiefTrader() internal view {
        require(msg.sender == chiefTrader, Exceptions.CHIEF_REQUIRED_EXCEPTION);
    }

    // TODO: move to base class
    function _safeApproveERC20TokenIfNecessary(address token, address to) internal {
        if (IERC20(token).allowance(to, address(this)) < type(uint256).max / 2)
            TransferHelper.safeApprove(token, to, type(uint256).max);
    }
}
