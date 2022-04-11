// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/cowswap/ICowswapSettlement.sol";
import "../interfaces/utils/ILStrategyOrderHelper.sol";
import "../libraries/external/GPv2Order.sol";
import "../libraries/ExceptionsLibrary.sol";

contract LStrategyOrderHelper is ILStrategyOrderHelper {
    // IMMUTABLES
    address public immutable erc20Vault;
    address public immutable lStrategy;
    address public immutable cowswap;
    bytes4 public constant SET_PRESIGNATURE_SELECTOR = 0xec6cb13f;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;

    constructor(
        address lStrategy_,
        address cowswap_,
        address erc20Vault_
    ) {
        lStrategy = lStrategy_;
        erc20Vault = erc20Vault_;
        cowswap = cowswap_;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    function checkOrder(
        GPv2Order.Data memory order,
        bytes calldata uuid,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) external view {
        require(msg.sender == lStrategy, ExceptionsLibrary.FORBIDDEN);
        require(deadline >= block.timestamp, ExceptionsLibrary.TIMESTAMP);
        (bytes32 orderHashFromUid, , ) = GPv2Order.extractOrderUidParams(uuid);
        bytes32 domainSeparator = ICowswapSettlement(cowswap).domainSeparator();
        bytes32 orderHash = GPv2Order.hash(order, domainSeparator);
        require(orderHash == orderHashFromUid, ExceptionsLibrary.INVARIANT);
        require(address(order.sellToken) == tokenIn, ExceptionsLibrary.INVALID_TOKEN);
        require(address(order.buyToken) == tokenOut, ExceptionsLibrary.INVALID_TOKEN);
        require(order.sellAmount == amountIn, ExceptionsLibrary.INVALID_VALUE);
        require(order.buyAmount >= minAmountOut, ExceptionsLibrary.LIMIT_UNDERFLOW);
        require(order.validTo <= deadline, ExceptionsLibrary.TIMESTAMP);
        require(order.receiver == erc20Vault, ExceptionsLibrary.FORBIDDEN);
    }
}
