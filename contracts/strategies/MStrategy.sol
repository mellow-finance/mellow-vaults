// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Multicall.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../interfaces/IVaultRegistry.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";

contract MStrategy is Multicall {
    using SafeERC20 for IERC20;

    // IMMUTABLES
    uint256 public constant DENOMINATOR = 10**9;
    bytes4 public constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 public constant EXACT_INPUT_SINGLE_SELECTOR = ISwapRouter.exactInputSingle.selector;
    bytes4 public constant EXACT_OUTPUT_SINGLE_SELECTOR = ISwapRouter.exactOutputSingle.selector;

    address[] public tokens;
    IERC20Vault public erc20Vault;
    IIntegrationVault public moneyVault;
    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool public pool;
    ISwapRouter public router;

    // INTERNAL STATE

    // MUTABLE PARAMS

    struct TickParams {
        int24 tickMin;
        int24 tickMax;
    }

    struct OracleParams {
        uint16 oracleObservationDelta;
        uint256 maxSlippageD;
    }

    struct RatioParams {
        uint256 erc20UniV3RatioD;
        uint256 erc20TokenRatioD;
    }
    struct BotParams {
        uint256 maxBotAllowance;
        uint256 minBotWaitTime;
    }

    struct OtherParams {
        uint16 intervalWidthInTicks;
        uint256 lowerTickDeviation;
        uint256 upperTickDeviation;
        uint256 minToken0ForOpening;
        uint256 minToken1ForOpening;
    }

    TickParams public tickParams;
    OracleParams public oracleParams;
    BotParams public botParams;
    OtherParams public otherParams;

    // @notice Constructor for a new contract
    // @param positionManager_ Reference to UniswapV3 positionManager
    // @param erc20vault_ Reference to ERC20 Vault
    // @param vault1_ Reference to Uniswap V3 Vault 1
    // @param vault2_ Reference to Uniswap V3 Vault 2

    // -------------------  EXTERNAL, VIEW  -------------------

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Manually pull tokens from fromVault to toVault
    /// @param fromVault Pull tokens from this vault
    /// @param toVault Pull tokens to this vault
    /// @param tokenAmounts Token amounts to pull
    function manualPull(
        IIntegrationVault fromVault,
        IIntegrationVault toVault,
        uint256[] memory tokenAmounts
    ) external {
        fromVault.pull(address(toVault), tokens, tokenAmounts, "");
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _priceX96FromTick(int24 _tick) internal pure returns (uint256) {
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(_tick);
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, CommonLibrary.Q96);
    }

    function _targetTokenRatioD(
        int24 tick,
        int24 tickMin,
        int24 tickMax
    ) internal pure returns (uint256) {
        if (tick <= tickMin) {
            return 0;
        }
        if (tick >= tickMax) {
            return DENOMINATOR;
        }
        return (uint256(uint24(tick - tickMin)) * DENOMINATOR) / uint256(uint24(tickMax - tickMin));
    }

    function _getAverageTick(IUniswapV3Pool pool_) internal view returns (int24 averageTick) {
        uint16 oracleObservationDelta = tickParams.oracleObservationDelta;

        (, , uint16 observationIndex, uint16 observationCardinality, , , ) = pool_.slot0();
        require(observationCardinality > oracleObservationDelta, ExceptionsLibrary.LIMIT_UNDERFLOW);
        (uint32 blockTimestamp, int56 tickCumulative, , ) = pool_.observations(observationIndex);

        uint16 observationIndexLast = observationIndex >= oracleObservationDelta
            ? observationIndex - oracleObservationDelta
            : observationIndex + (type(uint16).max - oracleObservationDelta + 1);
        (uint32 blockTimestampLast, int56 tickCumulativeLast, , ) = pool_.observations(observationIndexLast);

        uint32 timespan = blockTimestamp - blockTimestampLast;
        averageTick = int24((int256(tickCumulative) - int256(tickCumulativeLast)) / int256(uint256(timespan)));
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _rebalanceTokens(
        IUniswapV3Pool pool_,
        ISwapRouter router_,
        IIntegrationVault erc20Vault_,
        IIntegrationVault moneyVault_
    ) internal {
        int24 tickMin = tickParams.tickMin;
        int24 tickMax = tickParams.tickMax;
        int24 tick = _getAverageTick(pool_);
        uint256 targetTokenRatioD = _targetTokenRatioD(tick, tickMin, tickMax);
        (uint256[] memory erc20Tvl, ) = erc20Vault_.tvl();
        (uint256[] memory moneyTvl, ) = moneyVault_.tvl();
        uint256 token0 = erc20Tvl[0] + moneyTvl[0];
        uint256 token1 = erc20Tvl[1] + moneyTvl[1];
        uint256 priceX96 = _priceX96FromTick(tick);
        uint256 token1InToken0 = FullMath.mulDiv(token1, CommonLibrary.Q96, priceX96);
        uint256 targetToken0 = FullMath.mulDiv(token1InToken0 + token0, targetTokenRatioD, DENOMINATOR);
        bytes memory data;
        if (targetToken0 < token0) {
            uint256 amountIn = token0 - targetToken0;
            uint256 amountOutMinimum = FullMath.mulDiv(amountIn, CommonLibrary.Q96, priceX96);
            amountOutMinimum = FullMath.mulDiv(
                amountOutMinimum,
                DENOMINATOR - FullMath.mulDiv(oracleParams.maxSlippageD),
                DENOMINATOR
            );
            bytes memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                fee: pool_.fee(),
                recipient: address(erc20Vault),
                deadline: block.timestamp + 1,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });
            data = abi.encode(params);
        } else {
            uint256 amountIn = FullMath.mulDiv(targetToken0 - token0, CommonLibrary.Q96, priceX96);
        }
        erc20Vault.externalCall(abi.encodeWithSelector(EXACT_INPUT_SINGLE_SELECTOR, data));
    }

    function _swapToTarget(
        uint256 amountIn,
        uint256 amountOutMinimum,
        address tokenIn,
        address tokenOut,
        uint256 priceX96,
        uint256 ercTvl,
        IIntegrationVault erc20Vault_,
        IIntegrationVault moneyVault_
    ) external {
        if (amountIn > ercTvl) {
            moneyVault.pull()
        }
    }

    /// @notice Emitted when vault is swapped.
    /// @param oldNft UniV3 nft that was burned
    /// @param newNft UniV3 nft that was created
    /// @param newTickLower Lower tick for created UniV3 nft
    /// @param newTickUpper Upper tick for created UniV3 nft
    event SwapVault(uint256 oldNft, uint256 newNft, int24 newTickLower, int24 newTickUpper);

    /// @param fromVault The vault to pull liquidity from
    /// @param toVault The vault to pull liquidity to
    /// @param pulledAmounts amounts pulled from fromVault
    /// @param pushedAmounts amounts pushed to toVault
    /// @param liquidity The amount of liquidity. On overflow best effort pull is made
    event RebalancedUniV3(
        address fromVault,
        address toVault,
        uint256[] pulledAmounts,
        uint256[] pushedAmounts,
        uint128 liquidity
    );
}
