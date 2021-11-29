// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./external/yearn/IYearnVaultRegistry.sol";
import "./IVaultGovernance.sol";

interface IYearnVaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @param strategyTreasury Reference to address that will collect strategy fees
    struct DelayedStrategyParams {
        address strategyTreasury;
    }
    /// @notice Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param yearnVaultRegistry Reference to Yearn Vault Registry
    struct DelayedProtocolParams {
        IYearnVaultRegistry yearnVaultRegistry;
    }

    /// @notice Determines a corresponding Yearn vault for token
    /// @param token ERC-20 token for the yToken
    /// @return If there's a yToken returns its address, otherwise returns 0
    function yTokenForToken(address token) external view returns (address);

    /// @notice Delayed Strategy Params staged for commit after delay.
    /// @param nft VaultRegistry NFT of the vault
    function stagedDelayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory);

    /// @notice Delayed Strategy Params, i.e. Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @param nft VaultRegistry NFT of the vault
    function delayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory);

    /// @notice Delayed Protocol Params staged for commit after delay.
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function delayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Stage Delayed Strategy Params, i.e. Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params
    function stageDelayedStrategyParams(uint256 nft, DelayedStrategyParams calldata params) external;

    /// @notice Commit Delayed Strategy Params, i.e. Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedStrategyParamsTimestamp.
    /// @param nft VaultRegistry NFT of the vault
    function commitDelayedStrategyParams(uint256 nft) external;

    /// @notice Stage Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedProtocolParamsTimestamp.
    /// @param params New params
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external;

    /// @notice Commit Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function commitDelayedProtocolParams() external;

    /// @notice Sets the manual override for yToken vaults map
    /// @dev Can only be called by Protocol Admin
    /// @param token ERC-20 token for yToken
    /// @param yToken for ERC-20 token
    function setYTokenForToken(address token, address yToken) external;
}
