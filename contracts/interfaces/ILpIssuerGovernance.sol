// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IProtocolGovernance.sol";
import "./IVault.sol";

interface ILpIssuerGovernance {
    struct GovernanceParams {
        IVault gatewayVault;
        IProtocolGovernance protocolGovernance;
    }

    function governanceParams() external view returns (GovernanceParams memory);

    function pendingGovernanceParams() external view returns (GovernanceParams memory);

    function pendingGovernanceParamsTimestamp() external view returns (uint256);

    function setPendingGovernanceParams(GovernanceParams calldata newParams) external;

    function commitGovernanceParams() external;

    event SetPendingGovernanceParams(GovernanceParams);
    event CommitGovernanceParams(GovernanceParams);
}
