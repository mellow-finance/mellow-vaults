// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "./access/GovernanceAccessControl.sol";
import "./interfaces/IProtocolGovernance.sol";

contract VaultsGovernance is GovernanceAccessControl {
    bool public permissionless = true;
    IProtocolGovernance public protocolGovernance;

    bool public pendingPermissionless;
    IProtocolGovernance public pendingProtocolGovernance;

    uint256 public pendingPermissionlessTimestamp;
    uint256 public pendingProtocolGovernanceTimestamp;

    constructor(address _protocolGovernance) {
        protocolGovernance = IProtocolGovernance(_protocolGovernance);
    }

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    function setPendingPermissionless(bool _pendingPermissionless) external {
        require(_isGovernanceOrDelegate(), "PGD");
        pendingPermissionless = _pendingPermissionless;
        pendingPermissionlessTimestamp = block.timestamp + protocolGovernance.governanceDelay();
    }

    function setPendingGovernance(address _pendingProtocolGovernance) external {
        require(_isGovernanceOrDelegate(), "PGD");
        pendingProtocolGovernance = IProtocolGovernance(_pendingProtocolGovernance);
        pendingProtocolGovernanceTimestamp = block.timestamp + protocolGovernance.governanceDelay();
    }

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------
    function commitPermissionless() external {
        require(_isGovernanceOrDelegate(), "PGD");
        require((block.timestamp > pendingPermissionlessTimestamp) && (pendingPermissionlessTimestamp > 0), "TS");
        permissionless = pendingPermissionless;
        delete pendingPermissionless;
        delete pendingPermissionlessTimestamp;
    }

    function commitProtocolGovernance() external {
        require(_isGovernanceOrDelegate(), "PGD");
        require(
            (block.timestamp > pendingProtocolGovernanceTimestamp) && (pendingProtocolGovernanceTimestamp > 0),
            "TS"
        );
        protocolGovernance = pendingProtocolGovernance;
        delete pendingProtocolGovernance;
        delete pendingProtocolGovernanceTimestamp;
    }
}
