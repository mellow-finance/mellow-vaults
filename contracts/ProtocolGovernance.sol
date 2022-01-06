// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./utils/DefaultAccessControl.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice Governance that manages all params common for Mellow Permissionless Vaults protocol.
contract ProtocolGovernance is IProtocolGovernance, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 internal _stagedToCommitAt;

    mapping(address => uint256) private _stagedPermissionMasks;
    mapping(address => uint256) private _permissionMasks;
    EnumerableSet.AddressSet private _stagedAddresses;
    EnumerableSet.AddressSet private _addresses;

    uint256 public constant MAX_GOVERNANCE_DELAY = 7 days;
    uint256 public pendingParamsTimestamp;
    Params public params;
    Params public pendingParams;

    /// @notice Creates a new contract.
    /// @param admin Initial admin of the contract
    constructor(address admin) DefaultAccessControl(admin) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IProtocolGovernance
    function addresses() external view returns (address[] memory) {
        return _addresses.values();
    }

    /// @inheritdoc IProtocolGovernance
    function addressesLength() external view returns (uint256) {
        return _addresses.length();
    }

    /// @inheritdoc IProtocolGovernance
    function addressAt(uint256 index) external view returns (address) {
        return _addresses.at(index);
    }

    /// @inheritdoc IProtocolGovernance
    function permissionMask(address target) external view returns (uint256) {
        return _permissionMasks[target];
    }

    /// @inheritdoc IProtocolGovernance
    function stagedAddresses() external view returns (address[] memory) {
        return _stagedAddresses.values();
    }

    /// @inheritdoc IProtocolGovernance
    function stagedAddressesLength() external view returns (uint256) {
        return _stagedAddresses.length();
    }

    /// @inheritdoc IProtocolGovernance
    function stagedAddressAt(uint256 index) external view returns (address) {
        return _stagedAddresses.at(index);
    }

    /// @inheritdoc IProtocolGovernance
    function stagedPermissionMask(address target) external view returns (uint256) {
        return _stagedPermissionMasks[target];
    }

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

    /// @inheritdoc IProtocolGovernance
    function hasStagedAllPermissions(address target, uint8[] calldata permissionIds) external view returns (bool) {
        return _hasStagedAllPermissions(target, permissionIds);
    }

    /// @inheritdoc IProtocolGovernance
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


    function _hasPermission(address addr, uint8 permissionId) internal view returns (bool) {
        return (_permissionMasks[addr] & _permissionIdToMask(permissionId)) != 0;
    }

    function _hasAllPermissions(address addr, uint8[] calldata permissionIds) internal view returns (bool) {
        for (uint256 i; i < permissionIds.length; ++i) {
            if (!_hasPermission(addr, permissionIds[i])) {
                return false;
            }
        }
        return true;
    }

    function _hasStagedPermission(address addr, uint8 permissionId) internal view returns (bool) {
        return _stagedPermissionMasks[addr] & _permissionIdToMask(permissionId) != 0;
    }

    function _hasStagedAllPermissions(address addr, uint8[] calldata permissionIds) internal view returns (bool) {
        for (uint256 i; i < permissionIds.length; ++i) {
            if (!_hasStagedPermission(addr, permissionIds[i])) {
                return false;
            }
        }
        return true;
    }

    function _isStagedToCommit() private view returns (bool) {
        return _stagedToCommitAt != 0;
    }

    function _permissionIdToMask(uint8 permissionId) private pure returns (uint256) {
        return 1 << (permissionId);
    }

    function _clearStagedPermissions() private {
        uint256 length = _stagedAddresses.length();
        for (uint256 i; i != length; ++i) {
            address target = _stagedAddresses.at(i);
            delete _stagedPermissionMasks[target];
            _stagedAddresses.remove(target);
        }
    }

    function _revokePermissionInstant(address from, uint8 permissionId) private {
        uint256 diff = _permissionIdToMask(permissionId);
        uint256 currentMask = _permissionMasks[from];
        _permissionMasks[from] = currentMask & (~diff);
        if (_permissionMasks[from] == 0) {
            delete _permissionMasks[from];
            _addresses.remove(from);
        }
    }

    function _revokePermissionsInstant(address from, uint8[] calldata permissionIds) internal {
        for (uint256 i; i != permissionIds.length; ++i) {
            _revokePermissionInstant(from, permissionIds[i]);
        }
        emit RevokedPermissionsInstant(msg.sender, from, permissionIds);
    }

    function _stageGrantPermission(address to, uint8 permissionId) private {
        require(!_isStagedToCommit(), "Already staged");
        uint256 diff = _permissionIdToMask(permissionId);
        if (!_stagedAddresses.contains(to)) {
            _stagedAddresses.add(to);
            _stagedPermissionMasks[to] = _permissionMasks[to];
        }
        uint256 currentMask = _stagedPermissionMasks[to];
        _stagedPermissionMasks[to] = currentMask | diff;
    }

    function _rollbackStagedPermissions() internal {
        require(_isStagedToCommit(), ExceptionsLibrary.INVALID_STATE);
        delete _stagedAddresses;
        _clearStagedPermissions();
        delete _stagedToCommitAt;
        emit RolledBackStagedPermissions(msg.sender);
    }

    function _stageGrantPermissions(
        address to,
        uint8[] calldata permissionIds,
        uint256 delay
    ) internal {
        require(!_isStagedToCommit(), ExceptionsLibrary.INVALID_STATE);
        for (uint256 i; i != permissionIds.length; ++i) {
            _stageGrantPermission(to, permissionIds[i]);
        }
        _stagedToCommitAt = block.timestamp + delay;
        emit StagedGrantPermissions(msg.sender, to, permissionIds, delay);
    }

    function _commitStagedPermissions() internal {
        require(_isStagedToCommit(), ExceptionsLibrary.INVALID_STATE);
        require(block.timestamp >= _stagedToCommitAt, ExceptionsLibrary.TIMESTAMP);
        uint256 length = _stagedAddresses.length();
        for (uint256 i; i != length; ++i) {
            address delayedAddress = _stagedAddresses.at(i);
            uint256 delayedPermissionMask = _stagedPermissionMasks[delayedAddress];
            if (delayedPermissionMask == 0) {
                delete _permissionMasks[delayedAddress];
                _addresses.remove(delayedAddress);
            } else {
                _permissionMasks[delayedAddress] = delayedPermissionMask;
                _addresses.add(delayedAddress);
            }
        }
        _clearStagedPermissions();
        delete _stagedToCommitAt;
    }

    // ---------------------------------- PRIVATE -----------------------------------

    function _validateGovernanceParams(IProtocolGovernance.Params calldata newParams) private pure {
        require(newParams.maxTokensPerVault != 0 || newParams.governanceDelay != 0, ExceptionsLibrary.NULL);
        require(newParams.governanceDelay <= MAX_GOVERNANCE_DELAY, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    function _requireAdmin() private view {
        require(isAdmin(msg.sender), ExceptionsLibrary.FORBIDDEN);
    }

    // ---------------------------------- EVENTS ------------------------------------

    // Addresses
    event StagedGrantPermissions(address indexed sender, address indexed target, uint8[] permissionIds, uint256 delay);
    event RevokedPermissionsInstant(address indexed sender, address indexed target, uint8[] permissionIds);
    event RolledBackStagedPermissions(address indexed sender);
    event CommittedStagedPermissions(address indexed sender);

    // Params
    event PendingParamsSet(address indexed sender, uint256 at, Params params);
    event ParamsCommitted(address indexed sender);
}
