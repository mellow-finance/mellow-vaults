// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./IIntegrationVault.sol";
import "../external/pancakeswap/IPancakeNonfungiblePositionManager.sol";
import "../external/pancakeswap/IPancakeV3Pool.sol";

interface IPancakeSwapMerklVault is IERC721Receiver, IIntegrationVault {
    struct Options {
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Reference to IPancakeNonfungiblePositionManager of PancakeSwap protocol.
    function positionManager() external view returns (IPancakeNonfungiblePositionManager);

    /// @notice erc20 vault of the rootvault system
    function erc20Vault() external view returns (address);

    /// @notice Reference to PancakeV3Pool pool.
    function pool() external view returns (IPancakeV3Pool);

    /// @notice NFT of Pancake position manager
    function uniV3Nft() external view returns (uint256);

    /// @notice Returns tokenAmounts corresponding to liquidity, based on the current Uniswap position
    /// @param liquidity Liquidity that will be converted to token amounts
    /// @return tokenAmounts Token amounts for the specified liquidity
    function liquidityToTokenAmounts(uint128 liquidity) external view returns (uint256[] memory tokenAmounts);

    /// @notice Returns liquidity corresponding to token amounts, based on the current Uniswap position
    /// @param tokenAmounts Token amounts that will be converted to liquidity
    /// @return liquidity Liquidity for the specified token amounts
    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) external view returns (uint128 liquidity);

    function updateHelper(address newHelper) external;

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
        address uniV3Helper_,
        address erc20Vault_
    ) external;

    /// @notice Collect UniV3 fees to zero vault.
    function collectEarnings() external returns (uint256[] memory collectedEarnings);

    /// @notice collects all reward tokens from merkle distributor directly to lpFarm contract
    function compound(
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external returns (uint256[] memory claimedAmounts);
}
