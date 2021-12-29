// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "./DefaultAccessControl.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./libraries/AddressPermissions.sol";
import "./DelayedAddressPermissionControl.sol";

/// @notice Governance that manages all params common for Mellow Permissionless Vaults protocol.
contract ProtocolGovernance is IProtocolGovernance, DefaultAccessControl, DelayedAddressPermissionControl {
    uint256 public constant MAX_GOVERNANCE_DELAY = 7 days;
    uint256 public pendingParamsTimestamp;
    Params public params;
    Params public pendingParams;

    /// @notice Creates a new contract.
    /// @param admin Initial admin of the contract
    constructor(address admin) DefaultAccessControl(admin) {}

    // -------------------  PUBLIC, VIEW  -------------------

    function hasPermission(address target, uint8 permissionId) external view returns (bool) {
        return _hasPermission(target, permissionId);
    }

    function hasStagedPermission(address target, uint8 permissionId) external view returns (bool) {
        return _hasStagedPermission(target, permissionId);
    }

    function stagedToCommitAt() external view returns (uint256) {
        return _stagedToCommitAt;
    }

    /// @inheritdoc IProtocolGovernance
    function permissionless() external view returns (bool) {
        return params.permissionless;
    }

    /// @inheritdoc IProtocolGovernance
    function maxTokensPerVault() external view returns (uint256) {
        return params.maxTokensPerVault;
    }

    /// @inheritdoc IProtocolGovernance
    function governanceDelay() external view returns (uint256) {
        return params.governanceDelay;
    }

    /// @inheritdoc IProtocolGovernance
    function protocolTreasury() external view returns (address) {
        return params.protocolTreasury;
    }

    // ------------------- PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE -----------------

    function commitStagedPermissions() external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        _commitStagedPermissions();
    }

    function revokePermissionsInstant(address addr, uint8[] calldata permissionIds) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        _revokePermissionsInstant(addr, permissionIds);
    }

    /// @inheritdoc IProtocolGovernance
    function commitParams() external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        require(block.timestamp >= pendingParamsTimestamp, ExceptionsLibrary.TIMESTAMP);
        require(
            pendingParams.maxTokensPerVault != 0 || pendingParams.governanceDelay != 0,
            ExceptionsLibrary.EMPTY_PARAMS
        ); // sanity check for empty params
        params = pendingParams;
        delete pendingParams;
        delete pendingParamsTimestamp;
    }

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    function stageGrantPermissions(address target, uint8[] calldata permissionIds) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        _stageGrantPermissions(target, permissionIds, params.governanceDelay);
    }

    /// @inheritdoc IProtocolGovernance
    function setPendingParams(IProtocolGovernance.Params memory newParams) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        require(params.governanceDelay <= MAX_GOVERNANCE_DELAY, ExceptionsLibrary.MAX_GOVERNANCE_DELAY);
        pendingParams = newParams;
        pendingParamsTimestamp = block.timestamp + params.governanceDelay;
    }
}
