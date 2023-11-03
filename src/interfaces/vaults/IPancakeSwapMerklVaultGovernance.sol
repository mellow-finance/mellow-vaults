// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../external/pancakeswap/IPancakeNonfungiblePositionManager.sol";
import "../oracles/IOracle.sol";
import "./IVaultGovernance.sol";
import "./IPancakeSwapMerklVault.sol";

interface IPancakeSwapMerklVaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param positionManager Reference to PancakeSwap IPancakeNonfungiblePositionManager
    struct DelayedProtocolParams {
        IPancakeNonfungiblePositionManager positionManager;
        IOracle oracle;
    }

    /// @param safetyIndicesSet Safety indices for oracle
    struct DelayedStrategyParams {
        uint32 safetyIndicesSet;
    }

    struct StrategyParams {
        address merklFarm;
        address lpFarm;
    }

    /// @notice Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function delayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Delayed Protocol Params staged for commit after delay.
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Stage Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param params New params
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external;

    /// @notice Commit Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function commitDelayedProtocolParams() external;

    /// @notice Delayed Strategy Params
    /// @param nft VaultRegistry NFT of the vault
    function strategyParams(uint256 nft) external view returns (StrategyParams memory);

    /// @notice Delayed Strategy Params staged for commit after delay.
    /// @param nft VaultRegistry NFT of the vault
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external;

    /// @notice Delayed Strategy Params
    /// @param nft VaultRegistry NFT of the vault
    function delayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory);

    /// @notice Delayed Strategy Params staged for commit after delay.
    /// @param nft VaultRegistry NFT of the vault
    function stagedDelayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory);

    /// @notice Stage Delayed Strategy Params, i.e. Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params
    function stageDelayedStrategyParams(uint256 nft, DelayedStrategyParams calldata params) external;

    /// @notice Commit Delayed Strategy Params, i.e. Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedStrategyParamsTimestamp
    /// @param nft VaultRegistry NFT of the vault
    function commitDelayedStrategyParams(uint256 nft) external;

    /// @notice Deploys a new vault.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param owner_ Owner of the vault NFT
    /// @param fee_ Fee of the UniV3 pool
    /// @param helper_ address of helper for UniV3 arithmetic with ticks
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        uint24 fee_,
        address helper_,
        address erc20Vault_
    ) external returns (IPancakeSwapMerklVault vault, uint256 nft);
}
