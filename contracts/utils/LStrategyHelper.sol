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
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../libraries/external/PositionValue.sol";
import "../strategies/LStrategy.sol";

contract LStrategyHelper is ILStrategyHelper {
    // IMMUTABLES
    address public immutable cowswap;
    uint256 public constant D18 = 10**18;
    uint256 public constant DENOMINATOR = 10**9;

    constructor(address cowswap_) {
        cowswap = cowswap_;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    function checkOrder(
        GPv2Order.Data memory order,
        bytes calldata uuid,
        address erc20Vault,
        uint256 fee
    ) external view {
        (address tokenIn, address tokenOut, uint64 deadline, uint256 amountIn, uint256 minAmountOut) = LStrategy(
            msg.sender
        ).preOrder();
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

    function calculateTokenAmounts(
        IUniV3Vault lowerVault,
        IUniV3Vault upperVault,
        IVault erc20Vault,
        uint256 amount0,
        uint256 amount1,
        INonfungiblePositionManager positionManager
    ) external view returns (uint256[] memory lowerAmounts, uint256[] memory upperAmounts) {
        uint256 lowerVaultNft = lowerVault.uniV3Nft();
        uint256 upperVaultNft = upperVault.uniV3Nft();

        uint256[] memory lowerVaultTvl;
        uint256[] memory upperVaultTvl;

        {
            (, , , , , , , uint128 liquidityLower, , , , ) = positionManager.positions(lowerVaultNft);
            (, , , , , , , uint128 liquidityUpper, , , , ) = positionManager.positions(upperVaultNft);

            lowerVaultTvl = lowerVault.liquidityToTokenAmounts(liquidityLower);
            upperVaultTvl = upperVault.liquidityToTokenAmounts(liquidityUpper);
        }

        (uint256[] memory erc20VaultTvl, ) = erc20Vault.tvl();

        uint256 amount0Total;
        uint256 amount1Total;

        {
            (uint256 fees0Lower, uint256 fees1Lower) = PositionValue.fees(positionManager, lowerVaultNft);
            (uint256 fees0Upper, uint256 fees1Upper) = PositionValue.fees(positionManager, upperVaultNft);

            amount0Total = lowerVaultTvl[0] + upperVaultTvl[0] + erc20VaultTvl[0] + fees0Lower + fees0Upper;
            amount1Total = lowerVaultTvl[1] + upperVaultTvl[1] + erc20VaultTvl[1] + fees1Lower + fees1Upper;
        }

        lowerAmounts = new uint256[](2);
        lowerAmounts[0] = FullMath.mulDiv(lowerVaultTvl[0], amount0, amount0Total);
        lowerAmounts[1] = FullMath.mulDiv(lowerVaultTvl[1], amount1, amount1Total);
        upperAmounts = new uint256[](2);
        upperAmounts[0] = FullMath.mulDiv(upperVaultTvl[0], amount0, amount0Total);
        upperAmounts[1] = FullMath.mulDiv(upperVaultTvl[1], amount1, amount1Total);
    }

    function getPreOrder(uint256[] memory tvl, uint256 minAmountOut) external view returns (LStrategy.PreOrder memory) {
        LStrategy strategy = LStrategy(msg.sender);
        (IOracle oracle, uint32 maxSlippageD, uint32 orderDeadline, uint256 oracleSafetyMask, , ) = strategy
            .tradingParams();
        (, uint32 erc20TokenRatioD, , uint32 minErc20TokenRatioDeviationD, ) = strategy.ratioParams();

        uint256 priceX96 = strategy.getTargetPriceX96(strategy.tokens(0), strategy.tokens(1), oracle, oracleSafetyMask);
        (uint256 tokenDelta, bool isNegative) = _liquidityDelta(
            FullMath.mulDiv(tvl[0], priceX96, CommonLibrary.Q96),
            tvl[1],
            erc20TokenRatioD,
            minErc20TokenRatioDeviationD
        );

        uint256 isNegativeInt = isNegative ? 1 : 0;
        uint256[2] memory tokenValuesToTransfer = [
            FullMath.mulDiv(tokenDelta, CommonLibrary.Q96, priceX96),
            tokenDelta
        ];
        uint256 amountOut = FullMath.mulDiv(
            tokenValuesToTransfer[1 ^ isNegativeInt],
            DENOMINATOR - maxSlippageD,
            DENOMINATOR
        );
        amountOut = amountOut > minAmountOut ? amountOut : minAmountOut;
        return
            LStrategy.PreOrder({
                tokenIn: strategy.tokens(isNegativeInt),
                tokenOut: strategy.tokens(1 ^ isNegativeInt),
                deadline: uint64(block.timestamp + orderDeadline),
                amountIn: tokenValuesToTransfer[isNegativeInt],
                minAmountOut: amountOut
            });
    }

    /// @notice Liquidity required to be sold to reach targetLiquidityRatioD
    /// @param lowerLiquidity Lower vault liquidity
    /// @param upperLiquidity Upper vault liquidity
    /// @param targetLiquidityRatioD Target liquidity ratio (multiplied by DENOMINATOR)
    /// @param minDeviation Minimum allowed deviation between current and target liquidities (if the real is less, zero liquidity delta returned)
    /// @return delta Liquidity required to be sold from LowerVault (if isNegative is true) of to be bought to LowerVault (if isNegative is false) to reach targetLiquidityRatioD
    /// @return isNegative If `true` then delta needs to be bought to reach targetLiquidityRatioD, o/w needs to be sold
    function _liquidityDelta(
        uint256 lowerLiquidity,
        uint256 upperLiquidity,
        uint256 targetLiquidityRatioD,
        uint256 minDeviation
    ) internal pure returns (uint256 delta, bool isNegative) {
        uint256 targetLowerLiquidity = FullMath.mulDiv(
            targetLiquidityRatioD,
            lowerLiquidity + upperLiquidity,
            DENOMINATOR
        );
        if (minDeviation > 0) {
            uint256 liquidityRatioD = FullMath.mulDiv(lowerLiquidity, DENOMINATOR, lowerLiquidity + upperLiquidity);
            uint256 deviation = targetLiquidityRatioD > liquidityRatioD
                ? targetLiquidityRatioD - liquidityRatioD
                : liquidityRatioD - targetLiquidityRatioD;
            if (deviation < minDeviation) {
                return (0, false);
            }
        }
        if (targetLowerLiquidity > lowerLiquidity) {
            isNegative = true;
            delta = targetLowerLiquidity - lowerLiquidity;
        } else {
            isNegative = false;
            delta = lowerLiquidity - targetLowerLiquidity;
        }
    }
}
