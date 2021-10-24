// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IProtocolGovernance.sol";
import "./IVaultFactory.sol";
import "./IVaultGovernanceFactory.sol";

interface IVaultManagerGovernance {
    /// @notice Governance params of the Vault Manager
    /// @param permissionless Anyone can create a new vault
    /// @param protocolGovernance Governance of the protocol
    /// @param factory Vault Factory reference
    /// @param governanceFactory VaultGovernance Factory reference
    struct GovernanceParams {
        bool permissionless;
        IProtocolGovernance protocolGovernance;
        IVaultFactory factory;
        IVaultGovernanceFactory governanceFactory;
    }

    /// @notice Current governance params
    function governanceParams() external view returns (GovernanceParams memory);

    /// @notice Staged governance params
    function pendingGovernanceParams() external view returns (GovernanceParams memory);

    /// @notice When staged governance params can be committed
    function pendingGovernanceParamsTimestamp() external view returns (uint256);

    /// @notice Set staged governance params
    function setPendingGovernanceParams(GovernanceParams calldata newParams) external;

    /// @notice Commit staged governance params
    function commitGovernanceParams() external;

    event SetPendingGovernanceParams(GovernanceParams);
    event CommitGovernanceParams(GovernanceParams);
}
