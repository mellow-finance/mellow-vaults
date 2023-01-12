// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/external/cowswap/ICowswapSettlement.sol";
import "../interfaces/utils/ILStrategyHelper.sol";
import "../libraries/external/GPv2Order.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/FullMath.sol";
import "../interfaces/vaults/IVault.sol";


contract LStrategyHelper is ILStrategyHelper {
    // IMMUTABLES
    address public immutable cowswap;
    uint256 public constant D18 = 10**18;

    constructor(address cowswap_) {
        cowswap = cowswap_;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    function checkOrder(
        GPv2Order.Data memory order,
        bytes calldata uuid,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline,
        address erc20Vault,
        uint256 fee
    ) external view {
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
        require(order.kind == GPv2Order.KIND_SELL, ExceptionsLibrary.INVALID_VALUE);
        require(order.sellTokenBalance == GPv2Order.BALANCE_ERC20, ExceptionsLibrary.INVALID_VALUE);
        require(order.buyTokenBalance == GPv2Order.BALANCE_ERC20, ExceptionsLibrary.INVALID_VALUE);
        require(order.feeAmount <= fee, ExceptionsLibrary.INVALID_VALUE);
    }

    function tickFromPriceX96(uint256 priceX96) external pure returns (int24) {
        uint256 sqrtPriceX96 = CommonLibrary.sqrtX96(priceX96);
        return TickMath.getTickAtSqrtRatio(uint160(sqrtPriceX96));
    }

    function calculateTokenAmounts(IVault lowerVault, IVault upperVault, IVault erc20Vault, uint256 priceX96, uint256 amount0, uint256 amount1) external view returns (uint256[] memory lowerAmounts, uint256[] memory upperAmounts) {
        
        (uint256[] memory lowerVaultTvl, ) = lowerVault.tvl();
        (uint256[] memory upperVaultTvl, ) = upperVault.tvl();
        (uint256[] memory erc20VaultTvl, ) = erc20Vault.tvl();

        uint256 amount0Total = lowerVaultTvl[0] + upperVaultTvl[0] + erc20VaultTvl[0];
        uint256 amount1Total = lowerVaultTvl[1] + upperVaultTvl[1] + erc20VaultTvl[1];

        lowerAmounts = new uint256[](2);
        lowerAmounts[0] = FullMath.mulDiv(lowerVaultTvl[0], amount0, amount0Total);
        lowerAmounts[1] = FullMath.mulDiv(lowerVaultTvl[1], amount1, amount1Total);
        upperAmounts = new uint256[](2);
        upperAmounts[0] = FullMath.mulDiv(upperVaultTvl[0], amount0, amount0Total);
        upperAmounts[1] = FullMath.mulDiv(upperVaultTvl[1], amount1, amount1Total);
    }
}
