// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/IVaultRegistry.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../libraries/ExceptionsLibrary.sol";

contract LStrategy {
    uint16 public intervalWidthInTicks;
    IERC20Vault public erc20Vault;
    IUniV3Vault public lowerVault;
    IUniV3Vault public upperVault;
    INonfungiblePositionManager public positionManager;
    uint256 public minToken0ForOpening;
    uint256 public minToken1ForOpening;

    function _swapVaults() internal {
        lowerVault.collectEarnings();
        INonfungiblePositionManager positionManager_ = positionManager;
        (, uint256[] memory maxLowerTvl) = lowerVault.tvl();
        require(maxLowerTvl[0] + maxLowerTvl[1] == 0, ExceptionsLibrary.INVARIANT);
        uint256 lowerNft = upperVault.uniV3Nft();
        uint256 upperNft = upperVault.uniV3Nft();
        address token0;
        address token1;
        uint24 fee;
        {
            uint128 lowerLiquidity;
            uint128 lowerTokensOwed0;
            uint128 lowerTokensOwed1;

            (, , token0, token1, fee, , , lowerLiquidity, , , lowerTokensOwed0, lowerTokensOwed1) = positionManager_
                .positions(lowerNft);
            require(lowerLiquidity + lowerTokensOwed0 + lowerTokensOwed1 == 0, ExceptionsLibrary.INVARIANT);
        }
        (, , , , , int24 upperTickLower, int24 upperTickUpper, , , , , ) = positionManager_.positions(upperNft);
        int24 newTickLower = (upperTickLower + upperTickUpper) / 2;
        int24 newTickUpper = newTickLower + int24(uint24(intervalWidthInTicks));
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
        positionManager.safeTransferFrom(address(this), address(lowerVault), newNft);
        (lowerVault, upperVault) = (upperVault, lowerVault);
        // TODO: Where should old NFT go?
        emit SwapVault(tx.origin, msg.sender, lowerNft, newNft, newTickLower, newTickUpper);
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
