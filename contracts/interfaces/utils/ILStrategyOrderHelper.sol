// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../../libraries/external/GPv2Order.sol";

interface ILStrategyOrderHelper {
    function checkOrder(
        GPv2Order.Data memory order,
        bytes calldata uuid,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline,
        address erc20Vault
    ) external;
}
