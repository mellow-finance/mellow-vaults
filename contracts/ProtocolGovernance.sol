// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./utils/DefaultAccessControl.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice Governance that manages all params common for Mellow Permissionless Vaults protocol.
contract ProtocolGovernance is IProtocolGovernance, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAX_GOVERNANCE_DELAY = 7 days;

    mapping(address => uint256) public grantedPermissionAddressTimestamps;
    mapping(address => uint256) public stagedGrantedPermissionMasks;
    mapping(address => uint256) public permissionMasks;
    uint256 public pendingParamsTimestamp;
    Params public params;
    Params public pendingParams;

    EnumerableSet.AddressSet private _stagedGrantedPermissionAddresses;
    EnumerableSet.AddressSet private _permissionAddresses;

    /// @notice Creates a new contract.
    /// @param admin Initial admin of the contract
    constructor(address admin) DefaultAccessControl(admin) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IProtocolGovernance
    function permissionAddresses() external view returns (address[] memory) {
        return _permissionAddresses.values();
    }

    /// @inheritdoc IProtocolGovernance
    function permissionAddressesCount() external view returns (uint256) {
        return _permissionAddresses.length();
    }

    /// @inheritdoc IProtocolGovernance
    function permissionAddressAt(uint256 index) external view returns (address) {
        return _permissionAddresses.at(index);
    }

    /// @inheritdoc IProtocolGovernance
    function rawPermissionMask(address target) external view returns (uint256) {
        return permissionMasks[target];
    }

    /// @inheritdoc IProtocolGovernance
    function permissionMask(address target) external view returns (uint256) {
        return permissionMasks[target] | params.forceAllowMask;
    }

    /// @inheritdoc IProtocolGovernance
    function addressesByPermissionIdRaw(uint8 permissionId) external view returns (address[] memory addresses) {
        uint256 len = _permissionAddresses.length();
        address[] memory tempAddresses = new address[](len);
        uint256 addressesLen = 0;
        uint256 mask = 1 << permissionId;
        for (uint256 i = 0; i < len; i++) {
            address addr = _permissionAddresses.at(i);
            if (permissionMasks[addr] & mask != 0) {
                addresses[addressesLen] = addr;
                addressesLen++;
            }
        }
        addresses = new address[](addressesLen);
        for (uint256 i = 0; i < addressesLen; i++) {
            addresses[i] = tempAddresses[i];
        }
    }

    /// @inheritdoc IProtocolGovernance
    function stagedPermissionAddresses() external view returns (address[] memory) {
        return _stagedGrantedPermissionAddresses.values();
    }

    /// @inheritdoc IProtocolGovernance
    function hasPermission(address target, uint8 permissionId) external view returns (bool) {
        return ((permissionMasks[target] | params.forceAllowMask) & (1 << (permissionId))) != 0;
    }

    /// @inheritdoc IProtocolGovernance
    function hasAllPermissions(address target, uint8[] calldata permissionIds) external view returns (bool) {
        uint256 submask = _permissionIdsToMask(permissionIds);
        uint256 mask = permissionMasks[target] | params.forceAllowMask;
        return mask & submask == submask;
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

    /// @inheritdoc IProtocolGovernance
    function forceAllowMask() external view returns (uint256) {
        return params.forceAllowMask;
    }

    // ------------------- PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE -----------------

    /// @inheritdoc IProtocolGovernance
    function rollbackStagedGrantedPermissions() external {
        _requireAdmin();
        _clearStagedPermissions();
        emit RolledBackStagedGrantedPermissions(tx.origin, msg.sender);
    }

    /// @inheritdoc IProtocolGovernance
    function commitStagedPermissions() external {
        _requireAdmin();
        uint256 length = _stagedGrantedPermissionAddresses.length();
        for (uint256 i; i != length; ++i) {
            address stagedAddress = _stagedGrantedPermissionAddresses.at(i);
            if (block.timestamp >= grantedPermissionAddressTimestamps[stagedAddress]) {
                permissionMasks[stagedAddress] = stagedGrantedPermissionMasks[stagedAddress];
                if (permissionMasks[stagedAddress] == 0) {
                    _permissionAddresses.remove(stagedAddress);
                } else {
                    _permissionAddresses.add(stagedAddress);
                }
            }
        }
        _clearStagedPermissions();
        delete pendingParamsTimestamp;
    }

    /// @inheritdoc IProtocolGovernance
    function commitStagedPermission(address stagedAddress) external {
        _requireAdmin();
        uint256 stagedToCommitAt = grantedPermissionAddressTimestamps[stagedAddress];
        require(block.timestamp >= stagedToCommitAt, ExceptionsLibrary.TIMESTAMP);
        require(stagedToCommitAt != 0, ExceptionsLibrary.NULL);
        permissionMasks[stagedAddress] = stagedGrantedPermissionMasks[stagedAddress];
        if (permissionMasks[stagedAddress] == 0) {
            _permissionAddresses.remove(stagedAddress);
        } else {
            _permissionAddresses.add(stagedAddress);
        }
        emit CommittedStagedGrantedPermission(tx.origin, msg.sender, stagedAddress);
    }

    /// @inheritdoc IProtocolGovernance
    function revokePermissions(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
        uint256 diff;
        for (uint256 i = 0; i < permissionIds.length; ++i) {
            diff |= 1 << permissionIds[i];
        }
        uint256 currentMask = permissionMasks[target];
        uint256 newMask = currentMask & (~diff);
        permissionMasks[target] = newMask;
        if (newMask == 0) {
            _permissionAddresses.remove(target);
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
        emit ParamsCommitted(tx.origin, msg.sender, params);
    }

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    /// @inheritdoc IProtocolGovernance
    function stageGrantPermissions(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
        uint256 delay = params.governanceDelay;
        uint256 diff = _permissionIdsToMask(permissionIds);
        if (!_stagedGrantedPermissionAddresses.contains(target)) {
            _stagedGrantedPermissionAddresses.add(target);
            stagedGrantedPermissionMasks[target] = permissionMasks[target];
        }
        uint256 currentMask = stagedGrantedPermissionMasks[target];
        stagedGrantedPermissionMasks[target] = currentMask | diff;
        uint256 stagedToCommitAt = block.timestamp + delay;
        grantedPermissionAddressTimestamps[target] = stagedToCommitAt;
        emit StagedGrantPermissions(tx.origin, msg.sender, target, permissionIds, stagedToCommitAt);
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

    function _permissionIdsToMask(uint8[] calldata permissionIds) private pure returns (uint256 mask) {
        for (uint256 i = 0; i < permissionIds.length; ++i) {
            mask |= 1 << permissionIds[i];
        }
    }

    function _requireAdmin() private view {
        require(isAdmin(msg.sender), ExceptionsLibrary.FORBIDDEN);
    }

    // -------------------------------  PRIVATE, MUTATING  ---------------------------

    function _clearStagedPermissions() private {
        uint256 length = _stagedGrantedPermissionAddresses.length();
        for (uint256 __; __ != length; ++__) {
            // actual length is decremented in the loop so we take the first element each time
            address target = _stagedGrantedPermissionAddresses.at(0);
            delete stagedGrantedPermissionMasks[target];
            delete grantedPermissionAddressTimestamps[target];
            _stagedGrantedPermissionAddresses.remove(target);
        }
    }

    // ---------------------------------- EVENTS -------------------------------------

    /// @notice Emitted when new permissions are staged to be granted for speceific address.
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
    event RolledBackStagedGrantedPermissions(address indexed origin, address indexed sender);

    /// @notice Emitted when staged permissions are committed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    event CommittedStagedGrantedPermissions(address indexed origin, address indexed sender);

    /// @notice Emitted when staged permissions are comitted for speceific address
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param target Target address
    event CommittedStagedGrantedPermission(address indexed origin, address indexed sender, address indexed target);

    /// @notice Emitted when pending parameters are set
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param at Timestamp when the pending parameters could be committed
    /// @param params Pending parameters
    event PendingParamsSet(address indexed origin, address indexed sender, uint256 at, Params params);

    /// @notice Emitted when pending parameters are committed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params Committed parameters
    event ParamsCommitted(address indexed origin, address indexed sender, Params params);
}
