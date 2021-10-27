// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernance.sol";

interface IGatewayVaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay
    /// @param strategyTreasury Reference to address that will collect strategy fees
    /// @param redirects Redirects[i] is the number of subvault that will receive deposit to i-th subvault. If the array is empty it is ignored.
    struct DelayedStrategyParams {
        address strategyTreasury;
        address[] redirects;
    }
    /// @notice Params that could be changed by Strategy or Protocol Governance immediately
    /// @param limits Token limits for the vault
    struct StrategyParams {
        uint256[] limits;
    }

    /// @notice Delayed Strategy Params, i.e. Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay
    /// @param nft Nft of the vault
    function delayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory);

    /// @notice Delayed Strategy Params staged for commit after delay
    /// @param nft Nft of the vault
    function stagedDelayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory);

    /// @notice Strategy Params
    /// @param nft Nft of the vault
    function strategyParams(uint256 nft) external view returns (StrategyParams memory);

    /// @notice Stage Delayed Strategy Params
    /// @param nft Nft of the vault
    /// @param params New params
    function stageDelayedStrategyParams(uint256 nft, DelayedStrategyParams calldata params) external;

    /// @notice Commit Delayed Strategy Params
    function commitDelayedStrategyParams(uint256 nft) external;

    /// @notice Set immediate strategy params
    /// @dev Should require nft > 0
    /// @param nft Nft of the vault
    /// @param params New params
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external;

    event StageDelayedStrategyParams(
        address indexed origin,
        address indexed sender,
        uint256 indexed nft,
        DelayedStrategyParams params,
        uint256 when
    );
    event CommitDelayedStrategyParams(
        address indexed origin,
        address indexed sender,
        uint256 indexed nft,
        DelayedStrategyParams params
    );
    event SetStrategyParams(address indexed origin, address indexed sender, uint256 indexed nft, StrategyParams params);
}
