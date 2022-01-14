// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./utils/DefaultAccessControl.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice Governance that manages all params common for Mellow Permissionless Vaults protocol.
contract ProtocolGovernance is ERC165, IProtocolGovernance, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAX_GOVERNANCE_DELAY = 7 days;

    mapping(address => uint256) public stagedPermissionGrantsTimestamps;
    mapping(address => uint256) public stagedPermissionGrantsMasks;
    mapping(address => uint256) public permissionMasks;
    
    uint256 public pendingParamsTimestamp;
    Params public pendingParams;
    Params public params;

    EnumerableSet.AddressSet private _stagedPermissionGrantsAddresses;
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
    function stagedPermissionGrantsAddresses() external view returns (address[] memory) {
        return _stagedPermissionGrantsAddresses.values();
    }

    /// @inheritdoc IProtocolGovernance
    function addressesByPermission(uint8 permissionId) external view returns (address[] memory addresses) {
        uint256 length = _permissionAddresses.length();
        address[] memory tempAddresses = new address[](length);
        uint256 addressesLength = 0;
        uint256 mask = 1 << permissionId;
        for (uint256 i = 0; i < length; i++) {
            address addr = _permissionAddresses.at(i);
            if (permissionMasks[addr] & mask != 0) {
                tempAddresses[addressesLength] = addr;
                addressesLength++;
            }
        }
        // shrink to fit
        addresses = new address[](addressesLength);
        for (uint256 i = 0; i < addressesLength; i++) {
            addresses[i] = tempAddresses[i];
        }
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

    function supportsInterface(bytes4 interfaceId) public pure override(AccessControlEnumerable, ERC165) returns (bool) {
        return interfaceId == type(ERC165).interfaceId || interfaceId == type(IProtocolGovernance).interfaceId;
    }

    // ------------------- PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE -----------------

    /// @inheritdoc IProtocolGovernance
    function rollbackAllPermissionGrants() external {
        _requireAdmin();
        uint256 length = _stagedPermissionGrantsAddresses.length();
        for (uint256 __; __ != length; ++__) {
            // actual length is decremented in the loop so we take the first element each time
            address target = _stagedPermissionGrantsAddresses.at(0);
            delete stagedPermissionGrantsMasks[target];
            delete stagedPermissionGrantsTimestamps[target];
            _stagedPermissionGrantsAddresses.remove(target);
        }
        emit AllPermissionGrantsRolledBack(tx.origin, msg.sender);
    }

    /// @inheritdoc IProtocolGovernance
    function commitPermissionGrants(address stagedAddress) external {
        _requireAdmin();
        uint256 stagedToCommitAt = stagedPermissionGrantsTimestamps[stagedAddress];
        require(block.timestamp >= stagedToCommitAt, ExceptionsLibrary.TIMESTAMP);
        require(stagedToCommitAt != 0, ExceptionsLibrary.NULL);
        permissionMasks[stagedAddress] |= stagedPermissionGrantsMasks[stagedAddress];
        _permissionAddresses.add(stagedAddress);
        delete stagedPermissionGrantsMasks[stagedAddress];
        delete stagedPermissionGrantsTimestamps[stagedAddress];
        _stagedPermissionGrantsAddresses.remove(stagedAddress);
        emit PermissionGrantsCommitted(tx.origin, msg.sender, stagedAddress);
    }

    /// @inheritdoc IProtocolGovernance
    function commitAllPermissionGrantsSurpassedDelay() external returns (address[] memory) {
        _requireAdmin();
        uint256 length = _stagedPermissionGrantsAddresses.length();
        uint256 addressesLeft = length;
        address[] memory tempAddresses = new address[](length);
        for (uint256 i; i != addressesLeft;) {
            address stagedAddress = _stagedPermissionGrantsAddresses.at(i);
            if (block.timestamp >= stagedPermissionGrantsTimestamps[stagedAddress]) {
                permissionMasks[stagedAddress] |= stagedPermissionGrantsMasks[stagedAddress];
                _permissionAddresses.add(stagedAddress);
                delete stagedPermissionGrantsMasks[stagedAddress];
                delete stagedPermissionGrantsTimestamps[stagedAddress];
                _stagedPermissionGrantsAddresses.remove(stagedAddress);
                tempAddresses[length - addressesLeft] = stagedAddress;
                --addressesLeft;
                emit PermissionGrantsCommitted(tx.origin, msg.sender, stagedAddress);
            } else {
                ++i;
            }
        }
        // shrink to fit
        uint256 addressesToReturn = length - addressesLeft;
        address[] memory result = new address[](addressesToReturn);
        for (uint256 i; i != addressesToReturn; ++i) {
            result[i] = tempAddresses[i];
        }
        return result;
    }

    /// @inheritdoc IProtocolGovernance
    function revokePermissions(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
        require(target != address(0), ExceptionsLibrary.NULL);
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
        emit PermissionsRevoked(tx.origin, msg.sender, target, permissionIds);
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
        emit PendingParamsCommitted(tx.origin, msg.sender, params);
    }

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    /// @inheritdoc IProtocolGovernance
    function stagePermissionGrants(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
        require(target != address(0), ExceptionsLibrary.NULL);
        _stagedPermissionGrantsAddresses.add(target);
        stagedPermissionGrantsMasks[target] = _permissionIdsToMask(permissionIds);
        uint256 stagedToCommitAt = block.timestamp + params.governanceDelay;
        stagedPermissionGrantsTimestamps[target] = stagedToCommitAt;
        emit PermissionGrantsStaged(tx.origin, msg.sender, target, permissionIds, stagedToCommitAt);
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

    // ---------------------------------- EVENTS -------------------------------------

    /// @notice Emitted when new permissions are staged to be granted for speceific address.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param target Target address
    /// @param permissionIds Permission IDs to be granted
    /// @param at Timestamp when the staged permissions could be committed
    event PermissionGrantsStaged(
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
    event PermissionsRevoked(
        address indexed origin,
        address indexed sender,
        address indexed target,
        uint8[] permissionIds
    );

    /// @notice Emitted when staged permissions are rolled back
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    event AllPermissionGrantsRolledBack(address indexed origin, address indexed sender);

    /// @notice Emitted when staged permissions are comitted for speceific address
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param target Target address
    event PermissionGrantsCommitted(address indexed origin, address indexed sender, address indexed target);

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
    event PendingParamsCommitted(address indexed origin, address indexed sender, Params params);
}
