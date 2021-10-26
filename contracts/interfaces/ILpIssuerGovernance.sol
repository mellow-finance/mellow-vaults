// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IProtocolGovernance.sol";
import "./IVault.sol";

interface ILpIssuerGovernance {
    /// @notice A set of params that is managed by governance
    /// @param gatewayVault The gateway vault that is linked to the LpIssuer
    /// @param protocolGovernance Protocol Governance reference
    struct GovernanceParams {
        IVault gatewayVault;
        IProtocolGovernance protocolGovernance;
    }

    /// @notice Current governance params
    /// @return Current governance params
    function governanceParams() external view returns (GovernanceParams memory);

    /// @notice Governance params that will take effect once committed
    /// @return Pending governance params
    function pendingGovernanceParams() external view returns (GovernanceParams memory);

    /// @notice The timestamp when Pending Governance Params can be committed
    /// @return Timestamp in secs
    function pendingGovernanceParamsTimestamp() external view returns (uint256);

    /// @notice Stage params for commit. The params could be committed after pendingGovernanceParamsTimestamp.
    /// @param newParams New params to set
    function setPendingGovernanceParams(GovernanceParams calldata newParams) external;

    /// @notice Commit pending governance params so they take effect
    function commitGovernanceParams() external;

    event SetPendingGovernanceParams(GovernanceParams);
    event CommitGovernanceParams(GovernanceParams);
}
