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
    mapping(address => uint256) private _permissionsStagedToCommitAt;
    mapping(address => uint256) private _permissionMasks;
    EnumerableSet.AddressSet private _stagedPermissionAddresses;
    EnumerableSet.AddressSet private _permissionAddresses;

    uint256 public permissionAddressesStagedToCommitAt;

    uint256 public constant MAX_GOVERNANCE_DELAY = 7 days;
    uint256 public pendingParamsStagedToCommitAt;
    Params public params;
    Params public pendingParams;

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
        return _permissionMasks[target];
    }

    /// @inheritdoc IProtocolGovernance
    function permissionMask(address target) external view returns (uint256) {
        return _permissionMasks[target] | params.forceAllowMask;
    }

    /// @inheritdoc IProtocolGovernance
    function dirtyAddresses(uint8 permissionId) external view returns (address[] memory addresses) {
        uint256 len = _permissionAddresses.length();
        address[] memory tempAddresses = new address[](len);
        uint256 addressesLen = 0;
        uint256 mask = 1 << permissionId;
        for (uint256 i = 0; i < len; i++) {
            address addr = _permissionAddresses.at(i);
            if (_permissionMasks[addr] & mask != 0) {
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
        return _stagedPermissionAddresses.values();
    }

    /// @inheritdoc IProtocolGovernance
    function stagedPermissionMask(address target) external view returns (uint256) {
        return _stagedPermissionMasks[target];
    }

    /// @inheritdoc IProtocolGovernance
    function hasPermission(address target, uint8 permissionId) external view returns (bool) {
        return ((_permissionMasks[target] | params.forceAllowMask) & (1 << (permissionId))) != 0;
    }

    /// @inheritdoc IProtocolGovernance
    function hasAllPermissions(address target, uint8[] calldata permissionIds) external view returns (bool) {
        uint256 submask = _permissionIdsToMask(permissionIds);
        uint256 mask = _permissionMasks[target] | params.forceAllowMask;
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
    function rollbackStagedPermissions() external {
        _requireAdmin();
        require(_isStagedToCommit(), ExceptionsLibrary.INVALID_STATE);
        _clearStagedPermissions();
        delete permissionAddressesStagedToCommitAt;
        emit RolledBackStagedPermissions(tx.origin, msg.sender);
    }

    /// @inheritdoc IProtocolGovernance
    function commitStagedPermissions() external {
        _requireAdmin();
        require(_isStagedToCommit(), ExceptionsLibrary.INVALID_STATE);
        uint256 length = _stagedPermissionAddresses.length();
        for (uint256 i; i != length; ++i) {
            address stagedAddress = _stagedPermissionAddresses.at(i);
            if (block.timestamp >= _permissionsStagedToCommitAt[stagedAddress]) {
                _permissionMasks[stagedAddress] = _stagedPermissionMasks[stagedAddress];
                if (_permissionMasks[stagedAddress] == 0) {
                    _permissionAddresses.remove(stagedAddress);
                } else {
                    _permissionAddresses.add(stagedAddress);
                }
            }
        }
        _clearStagedPermissions();
        delete permissionAddressesStagedToCommitAt;
    }

    /// @inheritdoc IProtocolGovernance
    function revokePermissions(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
        uint256 diff;
        for (uint256 i = 0; i < permissionIds.length; ++i) {
            diff |= 1 << permissionIds[i];
        }
        uint256 currentMask = _permissionMasks[target];
        uint256 newMask = currentMask & (~diff);
        _permissionMasks[target] = newMask;
        if (newMask == 0) {
            _permissionAddresses.remove(target);
        }
        emit RevokedPermissions(tx.origin, msg.sender, target, permissionIds);
    }

    /// @inheritdoc IProtocolGovernance
    function commitParams() external {
        _requireAdmin();
        require(
            pendingParamsStagedToCommitAt != 0 && block.timestamp >= pendingParamsStagedToCommitAt,
            ExceptionsLibrary.TIMESTAMP
        );
        params = pendingParams;
        delete pendingParams;
        delete pendingParamsStagedToCommitAt;
        emit ParamsCommitted(tx.origin, msg.sender, params);
    }

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    /// @inheritdoc IProtocolGovernance
    function stageGrantPermissions(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
        uint256 delay = params.governanceDelay;
        uint256 diff = _permissionIdsToMask(permissionIds);
        if (!_stagedPermissionAddresses.contains(target)) {
            _stagedPermissionAddresses.add(target);
            _stagedPermissionMasks[target] = _permissionMasks[target];
        }
        uint256 currentMask = _stagedPermissionMasks[target];
        _stagedPermissionMasks[target] = currentMask | diff;
        _permissionsStagedToCommitAt[target] = block.timestamp + delay;
        emit StagedGrantPermissions(tx.origin, msg.sender, target, permissionIds, permissionAddressesStagedToCommitAt);
    }

    /// @inheritdoc IProtocolGovernance
    function setPendingParams(IProtocolGovernance.Params calldata newParams) external {
        _requireAdmin();
        _validateGovernanceParams(newParams);
        pendingParams = newParams;
        pendingParamsStagedToCommitAt = block.timestamp + params.governanceDelay;
        emit PendingParamsSet(tx.origin, msg.sender, pendingParamsStagedToCommitAt, pendingParams);
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

    function _isStagedToCommit() private view returns (bool) {
        return permissionAddressesStagedToCommitAt != 0;
    }

    // -------------------------------  PRIVATE, MUTATING  ---------------------------

    function _clearStagedPermissions() private {
        uint256 length = _stagedPermissionAddresses.length();
        for (uint256 __; __ != length; ++__) {
            // actual length is decremented in the loop so we take the first element each time
            address target = _stagedPermissionAddresses.at(0);
            delete _stagedPermissionMasks[target];
            delete _permissionsStagedToCommitAt[target];
            _stagedPermissionAddresses.remove(target);
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
    /// @param params Committed parameters
    event ParamsCommitted(address indexed origin, address indexed sender, Params params);
}
