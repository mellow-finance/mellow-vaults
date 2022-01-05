// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "./utils/DefaultAccessControl.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./utils/AddressPermissionControl.sol";

/// @notice Governance that manages all params common for Mellow Permissionless Vaults protocol.
contract ProtocolGovernance is IProtocolGovernance, DefaultAccessControl, AddressPermissionControl {
    uint256 public constant MAX_GOVERNANCE_DELAY = 7 days;
    uint256 public pendingParamsTimestamp;
    Params public params;
    Params public pendingParams;

    event PendingParamsSet(address indexed sender, uint256 at, Params params);
    event ParamsCommitted(address indexed sender);

    /// @notice Creates a new contract.
    /// @param admin Initial admin of the contract
    constructor(address admin) DefaultAccessControl(admin) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IProtocolGovernance
    function hasPermission(address target, uint8 permissionId) external view returns (bool) {
        return _hasPermission(target, permissionId);
    }

    /// @inheritdoc IProtocolGovernance
    function hasAllPermissions(address target, uint8[] calldata permissionIds) external view returns (bool) {
        return _hasAllPermissions(target, permissionIds);
    }

    /// @inheritdoc IProtocolGovernance
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

    function rollbackStagedPermissions() external {
        _requireAdmin();
        _rollbackStagedPermissions();
    }

    function commitStagedPermissions() external {
        _requireAdmin();
        _commitStagedPermissions();
    }

    function revokePermissionsInstant(address addr, uint8[] calldata permissionIds) external {
        _requireAdmin();
        _revokePermissionsInstant(addr, permissionIds);
    }

    /// @inheritdoc IProtocolGovernance
    function commitParams() external {
        _requireAdmin();
        require(
            pendingParamsTimestamp != 0 && block.timestamp >= pendingParamsTimestamp,
            ExceptionsLibrary.TIMESTAMP
        );
        params = pendingParams;
        delete pendingParams;
        delete pendingParamsTimestamp;
        emit ParamsCommitted(msg.sender);
    }

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    function stageGrantPermissions(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
        _stageGrantPermissions(target, permissionIds, params.governanceDelay);
    }

    /// @inheritdoc IProtocolGovernance
    function setPendingParams(IProtocolGovernance.Params calldata newParams) external {
        _requireAdmin();
        _validateGovernanceParams(newParams);
        pendingParams = newParams;
        pendingParamsTimestamp = block.timestamp + params.governanceDelay;
        emit PendingParamsSet(msg.sender, pendingParamsTimestamp, pendingParams);
    }

    // ---------------------------------- PRIVATE -----------------------------------

    function _validateGovernanceParams(IProtocolGovernance.Params calldata newParams) private pure {
        require(newParams.maxTokensPerVault != 0 || newParams.governanceDelay != 0, ExceptionsLibrary.NULL);
        require(newParams.governanceDelay <= MAX_GOVERNANCE_DELAY, ExceptionsLibrary.LIMIT_UNDERFLOW);
    }

    function _requireAdmin() private view {
        require(isAdmin(msg.sender), ExceptionsLibrary.FORBIDDEN);
    }
}
