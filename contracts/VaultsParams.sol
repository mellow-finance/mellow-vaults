// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "./access/GovernanceAccessControl.sol";

contract VaultsParams is GovernanceAccessControl {
    bool public permissionless = false;
    bool public pendingPermissionless;

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE  -------------------

    function setPendingPermissionless(bool _pendingPermissionless) external {
        require(_isGovernanceOrDelegate(), "PGD");
        pendingPermissionless = _pendingPermissionless;
    }

    function commitPendingPermissionless() external {
        require(_isGovernanceOrDelegate(), "PGD");
        permissionless = pendingPermissionless;
        pendingPermissionless = false;
    }
}
