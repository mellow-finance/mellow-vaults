// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "./access/GovernanceAccessControl.sol";
import "./interfaces/IProtocolGovernance.sol";

contract VaultsGovernance is GovernanceAccessControl {
    bool public permissionless = true;
    address public protocolGovernance;

    bool public pendingPermissionless;
    address public pendingProtocolGovernance;

    uint256 public pendingPermissionlessTimestamp;
    uint256 public pendingProtocolGovernanceTimestamp;

    constructor(address _protocolGovernance) {
        protocolGovernance = _protocolGovernance;
    }

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE  -------------------

    function setPendingPermissionless(bool _pendingPermissionless) external {
        require(_isGovernanceOrDelegate(), "PGD");
        pendingPermissionless = _pendingPermissionless;
        pendingPermissionlessTimestamp = block.timestamp + IProtocolGovernance(protocolGovernance).governanceDelay();
    }

    function commitPermissionless() external {
        require(_isGovernanceOrDelegate(), "PGD");
        require((block.timestamp > pendingPermissionlessTimestamp) && (pendingPermissionlessTimestamp > 0), "TS");
        permissionless = pendingPermissionless;
        delete pendingPermissionless;
    }
}
