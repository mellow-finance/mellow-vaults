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
    uint256 public constant DENOMINATOR = 10**9;

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
        
        uint256 minRatioD = type(uint256).max;
        if (lowerVaultTvl[0] + upperVaultTvl[0] > 0) {
            uint256 upperBoundRatioD = FullMath.mulDiv(amount0, DENOMINATOR, lowerVaultTvl[0] + upperVaultTvl[0]);
            if (upperBoundRatioD < minRatioD) {
                minRatioD = upperBoundRatioD;
            }
        }

        if (lowerVaultTvl[1] + upperVaultTvl[1] > 0) {
            uint256 upperBoundRatioD = FullMath.mulDiv(amount1, DENOMINATOR, lowerVaultTvl[1] + upperVaultTvl[1]);
            if (upperBoundRatioD < minRatioD) {
                minRatioD = upperBoundRatioD;
            }
        }

        uint256 lowerCapital = FullMath.mulDiv(lowerVaultTvl[0], priceX96, CommonLibrary.Q96) + lowerVaultTvl[1];
        uint256 upperCapital = FullMath.mulDiv(upperVaultTvl[0], priceX96, CommonLibrary.Q96) + upperVaultTvl[1];
        uint256 erc20Capital = FullMath.mulDiv(erc20VaultTvl[0], priceX96, CommonLibrary.Q96) + erc20VaultTvl[1];

        minRatioD = FullMath.mulDiv(minRatioD, lowerCapital + upperCapital, lowerCapital + upperCapital + erc20Capital);

        lowerAmounts = new uint256[](2);
        lowerAmounts[0] = FullMath.mulDiv(lowerVaultTvl[0], minRatioD, DENOMINATOR);
        lowerAmounts[1] = FullMath.mulDiv(lowerVaultTvl[1], minRatioD, DENOMINATOR);
        upperAmounts = new uint256[](2);
        upperAmounts[0] = FullMath.mulDiv(upperVaultTvl[0], minRatioD, DENOMINATOR);
        upperAmounts[1] = FullMath.mulDiv(upperVaultTvl[1], minRatioD, DENOMINATOR);
    }
}
