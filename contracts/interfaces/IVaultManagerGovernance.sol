// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IProtocolGovernance.sol";
import "./IVaultFactory.sol";
import "./IVaultGovernanceFactory.sol";

interface IVaultManagerGovernance {
    struct GovernanceParams {
        bool permissionless;
        IProtocolGovernance protocolGovernance;
        IVaultFactory factory;
        IVaultGovernanceFactory governanceFactory;
    }

    function governanceParams() external view returns (GovernanceParams memory);

    function pendingGovernanceParams() external view returns (GovernanceParams memory);

    function pendingGovernanceParamsTimestamp() external view returns (uint256);

    function setPendingGovernanceParams(GovernanceParams calldata newParams) external;

    function commitGovernanceParams() external;

    event SetPendingGovernanceParams(GovernanceParams);
    event CommitGovernanceParams(GovernanceParams);
}
