// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./GovernanceAccessControl.sol";
import "./libraries/Common.sol";

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultManagerGovernance.sol";

import "hardhat/console.sol";

contract VaultManagerGovernance is GovernanceAccessControl, IVaultManagerGovernance {
    GovernanceParams private _governanceParams;
    GovernanceParams private _pendingGovernanceParams;
    uint256 private _pendingGovernanceParamsTimestamp;

    constructor(bool permissionless, IProtocolGovernance protocolGovernance) {
        _governanceParams = GovernanceParams({permissionless: permissionless, protocolGovernance: protocolGovernance});
    }

    function governanceParams() public view returns (GovernanceParams memory) {
        return _governanceParams;
    }

    function pendingGovernanceParams() external view returns (GovernanceParams memory) {
        return _pendingGovernanceParams;
    }

    function pendingGovernanceParamsTimestamp() external view returns (uint256) {
        return _pendingGovernanceParamsTimestamp;
    }

    function setPendingGovernanceParams(GovernanceParams calldata newGovernanceParams) external {
        require(_isGovernanceOrDelegate(), "GD");
        require(address(newGovernanceParams.protocolGovernance) != address(0), "ZMG");
        _pendingGovernanceParams = newGovernanceParams;
        _pendingGovernanceParamsTimestamp = block.timestamp + _governanceParams.protocolGovernance.governanceDelay();
        emit SetPendingGovernanceParams(newGovernanceParams);
    }

    function commitGovernanceParams() external {
        require(_isGovernanceOrDelegate(), "GD");
        require(_pendingGovernanceParamsTimestamp > 0, "NULL");
        require(block.timestamp > _pendingGovernanceParamsTimestamp, "TS");
        _governanceParams = _pendingGovernanceParams;
        emit CommitGovernanceParams(_governanceParams);
    }
}
