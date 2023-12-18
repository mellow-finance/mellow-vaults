// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IVeloVault.sol";

import "../external/velo/INonfungiblePositionManager.sol";
import "../oracles/IOracle.sol";
import "./IVaultGovernance.sol";

interface IVeloVaultGovernance is IVaultGovernance {
    struct StrategyParams {
        address gauge;
        address farm;
    }

    /// @notice Delayed Strategy Params
    /// @param nft VaultRegistry NFT of the vault
    function strategyParams(uint256 nft) external view returns (StrategyParams memory);

    /// @notice Delayed Strategy Params staged for commit after delay.
    /// @param nft VaultRegistry NFT of the vault
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external;

    /// @notice Deploys a new vault.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param owner_ Owner of the vault NFT
    /// @param tickSpacing_ tickSpacing of Velodrome pool
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        int24 tickSpacing_
    ) external returns (IVeloVault vault, uint256 nft);
}
