// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./IIntegrationVault.sol";
import "../external/univ3/INonfungiblePositionManager.sol";
import "../external/univ3/IUniswapV3Pool.sol";

interface IUniV3Vault is IERC721Receiver, IIntegrationVault {
    struct Options {
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Reference to INonfungiblePositionManager of UniswapV3 protocol.
    function positionManager() external view returns (INonfungiblePositionManager);

    /// @notice Reference to UniswapV3 pool.
    function pool() external view returns (IUniswapV3Pool);

    /// @notice NFT of UniV3 position manager
    function uniV3Nft() external view returns (uint256);

    /// @notice Returns tokenAmounts corresponding to liquidity, based on the current Uniswap position
    /// @param liquidity Liquidity that will be converted to token amounts
    /// @return tokenAmounts Token amounts for the specified liquidity
    function liquidityToTokenAmounts(uint128 liquidity) external view returns (uint256[] memory tokenAmounts);

    /// @notice Returns liquidity corresponding to token amounts, based on the current Uniswap position
    /// @param tokenAmounts Token amounts that will be converted to liquidity
    /// @return liquidity Liquidity for the specified token amounts
    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) external view returns (uint128 liquidity);

    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param fee_ Fee of the UniV3 pool
    /// @param uniV3Helper_ address of helper for UniV3 arithmetic with ticks
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        uint24 fee_,
        address uniV3Helper_
    ) external;

    /// @notice Collect UniV3 fees to zero vault.
    function collectEarnings() external returns (uint256[] memory collectedEarnings);
}
