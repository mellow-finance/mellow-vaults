// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./utils/DefaultAccessControl.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice Governance that manages all params common for Mellow Permissionless Vaults protocol.
contract ProtocolGovernance is IProtocolGovernance, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => uint256) private _stagedPermissionMasks;
    mapping(address => uint256) private _permissionMasks;
    EnumerableSet.AddressSet private _stagedAddresses;
    EnumerableSet.AddressSet private _addresses;

    uint256 internal _stagedToCommitAt;

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
        return (_permissionMasks[target] & _permissionIdToMask(permissionId)) != 0;
    }

    /// @inheritdoc IProtocolGovernance
    function hasAllPermissions(address target, uint8[] calldata permissionIds) external view returns (bool) {
        uint256 submask = _permissionIdToMask(permissionIds[0]);
        uint256 mask = _permissionMasks[target];
        return (mask >= submask && mask & submask == mask - submask);
    }

    function hasStagedPermission(address target, uint8 permissionId) external view returns (bool) {
        return (_stagedPermissionMasks[target] & _permissionIdToMask(permissionId)) != 0;
    }

    /// @inheritdoc IProtocolGovernance
    function hasAllStagedPermissions(address target, uint8[] calldata permissionIds) external view returns (bool) {
        uint256 submask = _permissionIdsToMask(permissionIds);
        uint256 mask = _stagedPermissionMasks[target];
        return (mask >= submask && mask & submask == mask - submask);
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

    /// @inheritdoc IProtocolGovernance
    function rollbackStagedPermissions() external {
        _requireAdmin();
        require(_isStagedToCommit(), ExceptionsLibrary.INVALID_STATE);
        _clearStagedPermissions();
        delete _stagedToCommitAt;
        emit RolledBackStagedPermissions(tx.origin, msg.sender);
    }

    /// @inheritdoc IProtocolGovernance
    function commitStagedPermissions() external {
        _requireAdmin();
        require(_isStagedToCommit(), ExceptionsLibrary.INVALID_STATE);
        require(block.timestamp >= _stagedToCommitAt, ExceptionsLibrary.TIMESTAMP);
        uint256 length = _stagedAddresses.length();
        for (uint256 i; i != length; ++i) {
            address delayedAddress = _stagedAddresses.at(i);
            uint256 delayedPermissionMask = _stagedPermissionMasks[delayedAddress];
            _permissionMasks[delayedAddress] = delayedPermissionMask;
            if (delayedPermissionMask == 0) {
                _addresses.remove(delayedAddress);
            } else {
                _addresses.add(delayedAddress);
            }
        }
        _clearStagedPermissions();
        delete _stagedToCommitAt;
    }

    /// @inheritdoc IProtocolGovernance
    function revokePermissions(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
        uint256 diff = _permissionIdsToMask(permissionIds);
        uint256 currentMask = _permissionMasks[target];
        uint256 newMask = currentMask & (~ diff);
        _permissionMasks[target] = newMask;
        if (newMask == 0) {
            _addresses.remove(target);
        }
        emit RevokedPermissions(tx.origin, msg.sender, target, permissionIds);
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
        emit ParamsCommitted(tx.origin, msg.sender);
    }

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    /// @inheritdoc IProtocolGovernance
    function stageGrantPermissions(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
        require(!_isStagedToCommit(), ExceptionsLibrary.INVALID_STATE);
        uint256 delay = params.governanceDelay;
        uint256 diff = _permissionIdsToMask(permissionIds);
        if (!_stagedAddresses.contains(target)) {
            _stagedAddresses.add(target);
            _stagedPermissionMasks[target] = _permissionMasks[target];
        }
        uint256 currentMask = _stagedPermissionMasks[target];
        _stagedPermissionMasks[target] = currentMask | diff;
        _stagedToCommitAt = block.timestamp + delay;
        emit StagedGrantPermissions(tx.origin, msg.sender, target, permissionIds, _stagedToCommitAt);
    }

    /// @inheritdoc IProtocolGovernance
    function setPendingParams(IProtocolGovernance.Params calldata newParams) external {
        _requireAdmin();
        _validateGovernanceParams(newParams);
        pendingParams = newParams;
        pendingParamsTimestamp = block.timestamp + params.governanceDelay;
        emit PendingParamsSet(tx.origin, msg.sender, pendingParamsTimestamp, pendingParams);
    }

    // -------------------------  PRIVATE, PURE, VIEW  ------------------------------

    function _validateGovernanceParams(IProtocolGovernance.Params calldata newParams) private pure {
        require(newParams.maxTokensPerVault != 0 || newParams.governanceDelay != 0, ExceptionsLibrary.NULL);
        require(newParams.governanceDelay <= MAX_GOVERNANCE_DELAY, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    function _permissionIdToMask(uint8 permissionId) private pure returns (uint256) {
        return 1 << (permissionId);
    }

    function _permissionIdsToMask(uint8[] calldata permissionIds) private pure returns (uint256 mask) {
        for (uint256 i; i < permissionIds.length; ++i) {
            mask |= _permissionIdToMask(permissionIds[i]);
        }
    }

    function _requireAdmin() private view {
        require(isAdmin(msg.sender), ExceptionsLibrary.FORBIDDEN);
    }

    function _isStagedToCommit() private view returns (bool) {
        return _stagedToCommitAt != 0;
    }

    // -------------------------------  PRIVATE, MUTATING  ---------------------------

    function _clearStagedPermissions() private {
        uint256 length = _stagedAddresses.length();
        for (uint256 i; i != length; ++i) {
            address target = _stagedAddresses.at(i);
            delete _stagedPermissionMasks[target];
            _stagedAddresses.remove(target);
        }
    }

    // ---------------------------------- EVENTS -------------------------------------

    /// @notice Emitted when new permissions are staged to be granted
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param target Target address
    /// @param permissionIds Permission IDs to be granted
    /// @param at Timestamp when the staged permissions could be committed
    event StagedGrantPermissions(
        address indexed origin,
        address indexed sender,
        address indexed target,
        uint8[] permissionIds,
        uint256 at
    );

    /// @notice Emitted when permissions are revoked
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param target Target address
    /// @param permissionIds Permission IDs to be revoked
    event RevokedPermissions(
        address indexed origin,
        address indexed sender,
        address indexed target,
        uint8[] permissionIds
    );

    /// @notice Emitted when staged permissions are rolled back
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    event RolledBackStagedPermissions(address indexed origin, address indexed sender);

    /// @notice Emitted when staged permissions are committed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    event CommittedStagedPermissions(address indexed origin, address indexed sender);

    /// @notice Emitted when pending parameters are set
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param at Timestamp when the pending parameters could be committed
    /// @param params Pending parameters
    event PendingParamsSet(address indexed origin, address indexed sender, uint256 at, Params params);

    /// @notice Emitted when pending parameters are committed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    event ParamsCommitted(address indexed origin, address indexed sender);
}
