// SPDX-License-Identifier: GPL-2.0-or-later
// TODO: Check if GPL is fine
// TODO: Keeper rewards
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
    uint256 public constant DENOMINATOR = 10**9;
    address[] public tokens;
    uint16 public intervalWidthInTicks;
    IERC20Vault public erc20Vault;
    IUniV3Vault public lowerVault;
    IUniV3Vault public upperVault;
    INonfungiblePositionManager public positionManager;
    uint256 public minToken0ForOpening;
    uint256 public minToken1ForOpening;
    int24 public tickPoint;
    int24 public tickPointInOneYear;
    uint256 public tickPointTimestamp;
    uint256 public erc20UniV3RatioD;

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
        INonfungiblePositionManager positionManager_ = positionManager;
        (uint256 targetLiquidityRatioD, bool isNegativeLiquidityRatio) = _targetLiquidityRatio(positionManager_);
        // // we crossed the interval right to left
        if (isNegativeLiquidityRatio) {
            // pull max liquidity and swap intervals
            _rebalanceLiquidity(
                positionManager_,
                upperVault,
                lowerVault,
                type(uint128).max,
                withdrawOptions,
                depositOptions
            );
            _swapVaults(positionManager_, false);
            return;
        }
        // we crossed the interval left to right
        if (targetLiquidityRatioD > DENOMINATOR) {
            // pull max liquidity and swap intervals
            _rebalanceLiquidity(
                positionManager_,
                lowerVault,
                upperVault,
                type(uint128).max,
                withdrawOptions,
                depositOptions
            );
            _swapVaults(positionManager_, true);
            return;
        }

        (, , uint128 lowerLiquidity) = _getVaultStats(positionManager_, lowerVault);
        (, , uint128 upperLiquidity) = _getVaultStats(positionManager_, upperVault);
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
        _rebalanceLiquidity(positionManager_, fromVault, toVault, liquidityDelta, withdrawOptions, depositOptions);
    }

    function _rebalanceLiquidity(
        INonfungiblePositionManager positionManager_,
        IUniV3Vault fromVault,
        IUniV3Vault toVault,
        uint128 liquidity,
        IUniV3Vault.Options memory withdrawOptions,
        IUniV3Vault.Options memory depositOptions
    ) internal {
        uint256[] memory withdrawTokenAmounts = fromVault.liquidityToTokenAmounts(liquidity);
        (, , uint128 maxFromLiquidity) = _getVaultStats(positionManager_, fromVault);
        fromVault.pull(address(erc20Vault), tokens, withdrawTokenAmounts, abi.encode(withdrawOptions));
        // Approximately `liquidity` will be pulled unless `liquidity` is more than total liquidity in the vault
        uint128 pulledLiqudity = maxFromLiquidity > liquidity ? liquidity : maxFromLiquidity;
        uint256[] memory depositTokenAmounts = toVault.liquidityToTokenAmounts(pulledLiqudity);
        erc20Vault.pull(address(toVault), tokens, depositTokenAmounts, abi.encode(depositOptions));
    }

    // As the upper vault goes from 100% liquidity to 0% liquidty, price moves from middle of the lower interval to right of the lower interval
    function _targetLiquidityRatio(INonfungiblePositionManager positionManager_)
        internal
        view
        returns (uint256 liquidityRatioD, bool isNegative)
    {
        int24 targetTick = _targetTick();
        (int24 tickLower, int24 tickUpper, ) = _getVaultStats(positionManager_, lowerVault);
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
        int24 tickPoint_ = tickPoint;
        int24 tickPointInOneYear_ = tickPointInOneYear;
        int24 annualTickDelta = tickPointInOneYear_ - tickPoint_;
        if (annualTickDelta > 0) {
            return
                tickPoint_ +
                int24(uint24(FullMath.mulDiv(uint256(uint24(annualTickDelta)), timeDelta, CommonLibrary.YEAR)));
        } else {
            return
                tickPoint_ -
                int24(uint24(FullMath.mulDiv(uint256(uint24(-annualTickDelta)), timeDelta, CommonLibrary.YEAR)));
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

    function _getVaultStats(INonfungiblePositionManager positionManager_, IUniV3Vault vault)
        internal
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        uint256 nft = vault.uniV3Nft();
        (, , , , , tickLower, tickUpper, liquidity, , , , ) = positionManager_.positions(nft);
    }

    function _swapVaults(INonfungiblePositionManager positionManager_, bool positiveGrowth) internal {
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

            (, , token0, token1, fee, , , fromLiquidity, , , fromTokensOwed0, fromTokensOwed1) = positionManager_
                .positions(fromNft);
            require(fromLiquidity + fromTokensOwed0 + fromTokensOwed1 == 0, ExceptionsLibrary.INVARIANT);
        }
        (, , , , , int24 toTickLower, int24 toTickUpper, , , , , ) = positionManager_.positions(toNft);
        int24 newTickLower;
        int24 newTickUpper;
        if (positiveGrowth) {
            newTickLower = (toTickLower + toTickUpper) / 2;
            newTickUpper = newTickLower + int24(uint24(intervalWidthInTicks));
        } else {
            newTickUpper = (toTickLower + toTickUpper) / 2;
            newTickLower = newTickUpper - int24(uint24(intervalWidthInTicks));
        }
        (uint256 newNft, , , ) = positionManager_.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: newTickLower,
                tickUpper: newTickUpper,
                amount0Desired: minToken0ForOpening,
                amount1Desired: minToken1ForOpening,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 600
            })
        );
        positionManager.safeTransferFrom(address(this), address(fromVault), newNft);
        (lowerVault, upperVault) = (upperVault, lowerVault);
        // TODO: Where should old NFT go?
        emit SwapVault(tx.origin, msg.sender, fromNft, newNft, newTickLower, newTickUpper);
    }

    /// @notice Emitted when vault is swapped.
    /// @param origin Origin of the tx
    /// @param sender Sender of the tx
    /// @param oldNft UniV3 nft that was swapped
    /// @param oldNft UniV3 nft that was created
    /// @param newTickLower Lower tick for created UniV3 nft
    /// @param newTickUpper Upper tick for created UniV3 nft
    event SwapVault(
        address indexed origin,
        address indexed sender,
        uint256 oldNft,
        uint256 newNft,
        int24 newTickLower,
        int24 newTickUpper
    );
}
