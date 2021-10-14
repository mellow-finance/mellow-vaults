// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./DefaultAccessControl.sol";
import "./libraries/Common.sol";

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/ILpIssuerGovernance.sol";

contract LpIssuerGovernance is ILpIssuerGovernance {
    GovernanceParams private _governanceParams;
    GovernanceParams private _pendingGovernanceParams;
    uint256 private _pendingGovernanceParamsTimestamp;

    constructor(GovernanceParams memory params) {
        _governanceParams = params;
    }

    /// -------------------  PUBLIC, VIEW  -------------------

    function governanceParams() public view returns (GovernanceParams memory) {
        return _governanceParams;
    }

    function pendingGovernanceParams() external view returns (GovernanceParams memory) {
        return _pendingGovernanceParams;
    }

    function pendingGovernanceParamsTimestamp() external view returns (uint256) {
        return _pendingGovernanceParamsTimestamp;
    }

    /// -------------------  PUBLIC, PROTOCOL ADMIN  -------------------

    function setPendingGovernanceParams(GovernanceParams calldata newGovernanceParams) external {
        require(_isProtocolAdmin(), "ADM");
        require(address(newGovernanceParams.protocolGovernance) != address(0), "ZMG");
        _pendingGovernanceParams = newGovernanceParams;
        _pendingGovernanceParamsTimestamp = block.timestamp + _governanceParams.protocolGovernance.governanceDelay();
        emit SetPendingGovernanceParams(newGovernanceParams);
    }

    function commitGovernanceParams() external {
        require(_isProtocolAdmin(), "ADM");
        require(_pendingGovernanceParamsTimestamp > 0, "NULL");
        require(block.timestamp > _pendingGovernanceParamsTimestamp, "TS");
        _governanceParams = _pendingGovernanceParams;
        emit CommitGovernanceParams(_governanceParams);
    }

    /// -------------------  PRIVATE, VIEW  -------------------

    function _isProtocolAdmin() internal view returns (bool) {
        return _governanceParams.protocolGovernance.isAdmin();
    }
}
