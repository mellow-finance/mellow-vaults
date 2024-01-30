// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./IVeloVaultGovernance.sol";
import "./IIntegrationVault.sol";

import "../external/velo/INonfungiblePositionManager.sol";
import "../external/velo/ICLPool.sol";

import "../utils/IVeloHelper.sol";

interface IVeloVault is IERC721Receiver, IIntegrationVault {
    /// @notice Reference to INonfungiblePositionManager of Velodrome protocol.
    function positionManager() external view returns (INonfungiblePositionManager);

    /// @notice Reference to Velodrome pool.
    function pool() external view returns (ICLPool);

    /// @notice NFT of Velo position manager
    function tokenId() external view returns (uint256);

    function helper() external view returns (IVeloHelper);

    function strategyParams() external view returns (IVeloVaultGovernance.StrategyParams memory);

    /// @notice Returns tokenAmounts corresponding to liquidity, based on the current Velodrome position
    /// @param liquidity Liquidity that will be converted to token amounts
    /// @return tokenAmounts Token amounts for the specified liquidity
    function liquidityToTokenAmounts(uint128 liquidity) external view returns (uint256[] memory tokenAmounts);

    /// @notice Returns liquidity corresponding to token amounts, based on the current Velodrome position
    /// @param tokenAmounts Token amounts that will be converted to liquidity
    /// @return liquidity Liquidity for the specified token amounts
    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) external view returns (uint128 liquidity);

    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param tickSpacing_ CLPool tickspacing
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        int24 tickSpacing_
    ) external;

    function collectRewards() external;
}
