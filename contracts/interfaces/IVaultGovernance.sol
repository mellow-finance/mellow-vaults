// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IVaultGovernance {
    /// @notice Set delayed strategy params
    /// @param nft Nft of the vault
    /// @param params New params
    function stageDelayedStrategyParams(uint256 nft, bytes calldata params) external;

    /// @notice Commit delayed strategy params
    function commitDelayedStrategyParams(uint256 nft) external;

    /// @notice Set delayed protocol params
    /// @param nft Nft of the vault
    /// @param params New params
    function stageDelayedProtocolParams(uint256 nft, bytes calldata params) external;

    /// @notice Commit delayed protocol params
    /// @param nft Nft of the vault
    function commitDelayedProtocolParams(uint256 nft) external;

    /// @notice Set immediate strategy params
    /// @param nft Nft of the vault
    /// @param params New params
    function setStrategyParams(uint256 nft, bytes calldata params) external;

    /// @notice Set immediate protocol params
    /// @param nft Nft of the vault
    /// @param params New params
    function setProtocolParams(uint256 nft, bytes calldata params) external;

    /// @notice Set immediate protocol params
    /// @param params New params
    function setCommonProtocolParams(bytes calldata params) external;
}
