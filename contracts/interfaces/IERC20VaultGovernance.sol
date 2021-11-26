// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernance.sol";

interface IERC20VaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @param strategyTreasury Reference to address that will collect strategy fees
    /// @param redirects Redirects[i] is the number of subvault that will receive deposit to i-th subvault. If the array is empty it is ignored.
    struct DelayedStrategyParams {
        address strategyTreasury;
        address trader;
    }

    /// @notice Delayed Strategy Params, i.e. Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
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
}
