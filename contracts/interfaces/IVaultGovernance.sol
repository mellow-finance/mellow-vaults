// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IProtocolGovernance.sol";

interface IVaultGovernance {
    /// @notice Current Delayed Strategy params (i.e. could be changed by Strategy and Protocol Governance with delay from ProtocolGovernance)
    /// @dev The params could be committed after delayedStrategyParamsTimetamp
    /// @param nft Nft of the vault
    function delayedStrategyParams(uint256 nft) external view returns (bytes memory);

    /// @notice Delayed Strategy params (i.e. could be changed by Strategy and Protocol Governance with delay from ProtocolGovernance) staged for change
    /// @dev The params could be committed after delayedStrategyParamsTimetamp
    /// @param nft Nft of the vault
    function stagedDelayedStrategyParams(uint256 nft) external view returns (bytes memory);

    /// @notice Timestamp in unix time seconds after which staged Delayed Strategy Params could be committed
    /// @param nft Nft of the vault
    function delayedStrategyParamsTimetamp(uint256 nft) external view returns (uint256);

    /// @notice Current Delayed Protocol params (i.e. could be changed by Protocol Governance with delay from ProtocolGovernance)
    /// @dev The params could be committed after delayedStrategyParamsTimetamp
    /// @param nft Nft of the vault
    function delayedProtocolParams(uint256 nft) external view returns (bytes memory);

    /// @notice Delayed Protocol params (i.e. could be changed by Protocol Governance with delay from ProtocolGovernance) staged for change
    /// @dev The params could be committed after delayedStrategyParamsTimetamp
    /// @param nft Nft of the vault
    function stagedDelayedProtocolParams(uint256 nft) external view returns (bytes memory);

    /// @notice Timestamp in unix time seconds after which staged Delayed Protocol Params could be committed
    /// @param nft Nft of the vault
    function delayedProtocolParamsTimetamp(uint256 nft) external view returns (uint256);

    /// @notice Protocol Governance reference staged for change
    /// @dev The params could be committed after delayedStrategyParamsTimetamp
    /// @param nft Nft of the vault
    function stagedProtocolGovernanceParams(uint256 nft) external view returns (IProtocolGovernance);

    /// @notice Timestamp in unix time seconds after which staged Protocol Governance could be committed
    /// @param nft Nft of the vault
    function delayedProtocolGovernanceTimetamp(uint256 nft) external view returns (uint256);

    /// @notice Strategy params (i.e. could be changed by Strategy and Protocol Governance immediately)
    /// @param nft Nft of the vault
    function strategyParams(uint256 nft) external view returns (bytes memory);

    /// @notice Protocol params (i.e. could be changed by Protocol Governance immediately)
    /// @param nft Nft of the vault
    function protocolParams(uint256 nft) external view returns (bytes memory);

    /// @notice Set delayed strategy params
    /// @dev Should require nft > 0
    /// @param nft Nft of the vault
    /// @param params New params
    function stageDelayedStrategyParams(uint256 nft, bytes calldata params) external;

    /// @notice Commit delayed strategy params
    function commitDelayedStrategyParams(uint256 nft) external;

    /// @notice Stage new Protocol Governance reference
    /// @param nft Nft of the vault
    /// @param newGovernance New Protocol Governance reference
    function stageProtocolGovernance(uint256 nft, IProtocolGovernance newGovernance) external;

    /// @notice Commit new ProtocolGovernance
    /// @param nft Nft of the vault
    function commitProtocolGovernance(uint256 nft) external;

    /// @notice Set delayed protocol params
    /// @param nft Nft of the vault
    /// @param params New params
    function stageDelayedProtocolParams(uint256 nft, bytes calldata params) external;

    /// @notice Commit delayed protocol params
    /// @dev VaultRegistry guarantees `nft > 0`, so `nft == 0` is reserved for params common for all vaults
    /// @param nft Nft of the vault
    function commitDelayedProtocolParams(uint256 nft) external;

    /// @notice Set immediate strategy params
    /// @dev Should require nft > 0
    /// @param nft Nft of the vault
    /// @param params New params
    function setStrategyParams(uint256 nft, bytes calldata params) external;

    /// @notice Set immediate protocol params
    /// @dev VaultRegistry guarantees `nft > 0`, so `nft == 0` is reserved for params common for all vaults
    /// @param nft Nft of the vault
    /// @param params New params
    function setProtocolParams(uint256 nft, bytes calldata params) external;
}
