// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Multicall.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/IVaultRegistry.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";

contract LStrategy is Multicall {
    // IMMUTABLES
    uint256 public constant DENOMINATOR = 10**9;
    address[] public tokens;
    IERC20Vault public immutable erc20Vault;
    INonfungiblePositionManager public immutable positionManager;

    // INTERNAL STATE

    IUniV3Vault public lowerVault;
    IUniV3Vault public upperVault;
    uint256 public tickPointTimestamp;

    // MUTABLE PARAMS

    struct TickParams {
        int24 tickPoint;
        int24 annualTickGrowth;
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
    RatioParams public ratioParams;
    BotParams public botParams;
    OtherParams public otherParams;

    // @notice Constructor for a new contract
    // @param positionManager_ Reference to UniswapV3 positionManager
    // @param erc20vault_ Reference to ERC20 Vault
    // @param vault1_ Reference to Uniswap V3 Vault 1
    // @param vault2_ Reference to Uniswap V3 Vault 2
    constructor(
        INonfungiblePositionManager positionManager_,
        IERC20Vault erc20vault_,
        IUniV3Vault vault1_,
        IUniV3Vault vault2_
    ) {
        positionManager = positionManager_;
        erc20Vault = erc20vault_;
        lowerVault = vault1_;
        upperVault = vault2_;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    // -------------------  EXTERNAL, MUTATING  -------------------

    // -------------------  INTERNAL, VIEW  -------------------

    function pullFromUniV3Vault(
        IUniV3Vault fromVault,
        uint256[] memory tokenAmounts,
        IUniV3Vault.Options memory withdrawOptions
    ) external {
        fromVault.pull(address(erc20Vault), tokens, tokenAmounts, abi.encode(withdrawOptions));
    }

    function pullFromERC20Vault(
        IUniV3Vault toVault,
        uint256[] memory tokenAmounts,
        IUniV3Vault.Options memory depositOptions
    ) external {
        erc20Vault.pull(address(toVault), tokens, tokenAmounts, abi.encode(depositOptions));
    }

    function rebalanceUniV3Vaults(IUniV3Vault.Options memory withdrawOptions, IUniV3Vault.Options memory depositOptions)
        external
    {
        (uint256 targetLiquidityRatioD, bool isNegativeLiquidityRatio) = _targetLiquidityRatio();
        // // we crossed the interval right to left
        if (isNegativeLiquidityRatio) {
            // pull max liquidity and swap intervals
            _rebalanceLiquidity(upperVault, lowerVault, type(uint128).max, withdrawOptions, depositOptions);
            _swapVaults(false);
            return;
        }
        // we crossed the interval left to right
        if (targetLiquidityRatioD > DENOMINATOR) {
            // pull max liquidity and swap intervals
            _rebalanceLiquidity(lowerVault, upperVault, type(uint128).max, withdrawOptions, depositOptions);
            _swapVaults(true);
            return;
        }

        (, , uint128 lowerLiquidity) = _getVaultStats(lowerVault);
        (, , uint128 upperLiquidity) = _getVaultStats(upperVault);
        (uint128 liquidityDelta, bool isNegativeLiquidityDelta) = _liquidityDelta(
            lowerLiquidity,
            upperLiquidity,
            targetLiquidityRatioD
        );
        IUniV3Vault fromVault;
        IUniV3Vault toVault;
        if (isNegativeLiquidityDelta) {
            fromVault = upperVault;
            toVault = lowerVault;
        } else {
            fromVault = lowerVault;
            toVault = upperVault;
        }
        _rebalanceLiquidity(fromVault, toVault, liquidityDelta, withdrawOptions, depositOptions);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    // As the upper vault goes from 100% liquidity to 0% liquidty, price moves from middle of the lower interval to right of the lower interval
    function _targetLiquidityRatio() internal view returns (uint256 liquidityRatioD, bool isNegative) {
        int24 targetTick = _targetTick();
        (int24 tickLower, int24 tickUpper, ) = _getVaultStats(lowerVault);
        int24 midTick = (tickUpper + tickLower) / 2;
        isNegative = midTick > targetTick;
        if (isNegative) {
            liquidityRatioD = FullMath.mulDiv(
                uint256(uint24(midTick - targetTick)),
                DENOMINATOR,
                uint256(uint24((tickUpper - tickLower) / 2))
            );
        } else {
            liquidityRatioD = FullMath.mulDiv(
                uint256(uint24(targetTick - midTick)),
                DENOMINATOR,
                uint256(uint24((tickUpper - tickLower) / 2))
            );
        }
    }

    function _targetTick() internal view returns (int24) {
        uint256 timeDelta = block.timestamp - tickPointTimestamp;
        int24 annualTickGrowth = tickParams.annualTickGrowth;
        int24 tickPoint = tickParams.tickPoint;
        if (annualTickGrowth > 0) {
            return
                tickPoint +
                int24(uint24(FullMath.mulDiv(uint256(uint24(annualTickGrowth)), timeDelta, CommonLibrary.YEAR)));
        } else {
            return
                tickPoint -
                int24(uint24(FullMath.mulDiv(uint256(uint24(-annualTickGrowth)), timeDelta, CommonLibrary.YEAR)));
        }
    }

    function _liquidityDelta(
        uint128 lowerLiquidity,
        uint128 upperLiquidity,
        uint256 targetLiquidityRatioD
    ) internal pure returns (uint128 delta, bool isNegative) {
        uint128 targetLowerLiquidity = uint128(
            FullMath.mulDiv(targetLiquidityRatioD, uint256(lowerLiquidity + upperLiquidity), DENOMINATOR)
        );
        if (targetLowerLiquidity > lowerLiquidity) {
            isNegative = true;
            delta = targetLowerLiquidity - lowerLiquidity;
        } else {
            isNegative = false;
            delta = lowerLiquidity - targetLowerLiquidity;
        }
    }

    function _getVaultStats(IUniV3Vault vault)
        internal
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        uint256 nft = vault.uniV3Nft();
        (, , , , , tickLower, tickUpper, liquidity, , , , ) = positionManager.positions(nft);
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _rebalanceLiquidity(
        IUniV3Vault fromVault,
        IUniV3Vault toVault,
        uint128 liquidity,
        IUniV3Vault.Options memory withdrawOptions,
        IUniV3Vault.Options memory depositOptions
    ) internal {
        uint256[] memory withdrawTokenAmounts = fromVault.liquidityToTokenAmounts(liquidity);
        (, , uint128 maxFromLiquidity) = _getVaultStats(fromVault);
        fromVault.pull(address(erc20Vault), tokens, withdrawTokenAmounts, abi.encode(withdrawOptions));
        // Approximately `liquidity` will be pulled unless `liquidity` is more than total liquidity in the vault
        uint128 pulledLiqudity = maxFromLiquidity > liquidity ? liquidity : maxFromLiquidity;
        uint256[] memory depositTokenAmounts = toVault.liquidityToTokenAmounts(pulledLiqudity);
        erc20Vault.pull(address(toVault), tokens, depositTokenAmounts, abi.encode(depositOptions));
    }

    function _swapVaults(bool positiveGrowth) internal {
        IUniV3Vault fromVault;
        IUniV3Vault toVault;
        if (!positiveGrowth) {
            fromVault = lowerVault;
            toVault = upperVault;
        } else {
            fromVault = upperVault;
            toVault = lowerVault;
        }
        fromVault.collectEarnings();
        uint256 fromNft = fromVault.uniV3Nft();
        uint256 toNft = toVault.uniV3Nft();
        address token0;
        address token1;
        uint24 fee;
        {
            uint128 fromLiquidity;
            uint128 fromTokensOwed0;
            uint128 fromTokensOwed1;

            (, , token0, token1, fee, , , fromLiquidity, , , fromTokensOwed0, fromTokensOwed1) = positionManager
                .positions(fromNft);
            require(fromLiquidity + fromTokensOwed0 + fromTokensOwed1 == 0, ExceptionsLibrary.INVARIANT);
        }
        (, , , , , int24 toTickLower, int24 toTickUpper, , , , , ) = positionManager.positions(toNft);
        int24 newTickLower;
        int24 newTickUpper;
        {
            uint16 intervalWidthInTicks = otherParams.intervalWidthInTicks;
            if (positiveGrowth) {
                newTickLower = (toTickLower + toTickUpper) / 2;
                newTickUpper = newTickLower + int24(uint24(intervalWidthInTicks));
            } else {
                newTickUpper = (toTickLower + toTickUpper) / 2;
                newTickLower = newTickUpper - int24(uint24(intervalWidthInTicks));
            }
        }
        (uint256 newNft, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: newTickLower,
                tickUpper: newTickUpper,
                amount0Desired: otherParams.minToken0ForOpening,
                amount1Desired: otherParams.minToken0ForOpening,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 600
            })
        );
        positionManager.safeTransferFrom(address(this), address(fromVault), newNft);
        (lowerVault, upperVault) = (upperVault, lowerVault);
        positionManager.burn(fromNft);
        emit SwapVault(fromNft, newNft, newTickLower, newTickUpper);
    }

    /// @notice Emitted when vault is swapped.
    /// @param oldNft UniV3 nft that was burned
    /// @param newNft UniV3 nft that was created
    /// @param newTickLower Lower tick for created UniV3 nft
    /// @param newTickUpper Upper tick for created UniV3 nft
    event SwapVault(uint256 oldNft, uint256 newNft, int24 newTickLower, int24 newTickUpper);
}
