// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/utils/IContractMeta.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./UnitPricesGovernance.sol";

/// @notice Governance that manages all params common for Mellow Permissionless Vaults protocol.
contract ProtocolGovernance is IContractMeta, IProtocolGovernance, ERC165, UnitPricesGovernance, Multicall {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant CONTRACT_NAME = "ProtocolGovernance";
    bytes32 public constant CONTRACT_VERSION = "1.0.0";

    uint256 public constant MAX_GOVERNANCE_DELAY = 7 days;
    uint256 public constant MIN_WITHDRAW_LIMIT = 200_000;

    mapping(address => uint256) public stagedPermissionGrantsTimestamps;
    mapping(address => uint256) public stagedPermissionGrantsMasks;
    mapping(address => uint256) public permissionMasks;
    EnumerableSet.AddressSet private _stagedPermissionGrantsAddresses;
    EnumerableSet.AddressSet private _permissionAddresses;

    /// @inheritdoc IProtocolGovernance
    mapping(address => uint256) public stagedValidatorsTimestamps;
    /// @inheritdoc IProtocolGovernance
    mapping(address => address) public stagedValidators;
    /// @inheritdoc IProtocolGovernance
    mapping(address => address) public validators;
    EnumerableSet.AddressSet private _stagedValidatorsAddresses;
    EnumerableSet.AddressSet private _validatorsAddresses;

    Params public params;
    Params public pendingParams;
    uint256 public pendingParamsTimestamp;

    /// @notice Creates a new contract.
    /// @param admin Initial admin of the contract
    constructor(address admin) UnitPricesGovernance(admin) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IProtocolGovernance
    function stagedValidatorsAddresses() external view returns (address[] memory) {
        return _stagedValidatorsAddresses.values();
    }

    /// @inheritdoc IProtocolGovernance
    function validatorsAddresses() external view returns (address[] memory) {
        return _validatorsAddresses.values();
    }

    /// @inheritdoc IProtocolGovernance
    function validatorsAddress(uint256 i) external view returns (address) {
        return _validatorsAddresses.at(i);
    }

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
                addresses[addressesLength] = addr;
                addressesLength++;
            }
        }
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

    /// @inheritdoc IProtocolGovernance
    function withdrawLimit(address token) external view returns (uint256) {
        return params.withdrawLimit * unitPrices[token];
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(UnitPricesGovernance, IERC165, ERC165)
        returns (bool)
    {
        return (interfaceId == type(IProtocolGovernance).interfaceId) || super.supportsInterface(interfaceId);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IProtocolGovernance
    function stageValidator(address target, address validator) external {
        _requireAdmin();
        _stagedValidatorsAddresses.add(target);
        stagedValidators[target] = validator;
        uint256 at = block.timestamp + params.governanceDelay;
        stagedValidatorsTimestamps[target] = at;
        emit ValidatorStaged(tx.origin, msg.sender, target, validator, at);
    }

    /// @inheritdoc IProtocolGovernance
    function rollbackStagedValidators() external {
        _requireAdmin();
        uint256 length = _stagedValidatorsAddresses.length();
        for (uint256 i; i != length; ++i) {
            address target = _stagedValidatorsAddresses.at(0);
            delete stagedValidators[target];
            delete stagedValidatorsTimestamps[target];
            _stagedValidatorsAddresses.remove(target);
        }
        emit AllStagedValidatorsRolledBack(tx.origin, msg.sender);
    }

    /// @inheritdoc IProtocolGovernance
    function commitValidator(address stagedAddress) external {
        _requireAdmin();
        uint256 stagedToCommitAt = stagedValidatorsTimestamps[stagedAddress];
        require(block.timestamp >= stagedToCommitAt, ExceptionsLibrary.TIMESTAMP);
        require(stagedToCommitAt != 0, ExceptionsLibrary.NULL);
        validators[stagedAddress] = stagedValidators[stagedAddress];
        if (validators[stagedAddress] == address(0)) {
            _validatorsAddresses.remove(stagedAddress);
        } else {
            _validatorsAddresses.add(stagedAddress);
        }
        delete stagedValidators[stagedAddress];
        delete stagedValidatorsTimestamps[stagedAddress];
        _stagedValidatorsAddresses.remove(stagedAddress);
        emit ValidatorCommitted(tx.origin, msg.sender, stagedAddress);
    }

    /// @inheritdoc IProtocolGovernance
    function commitAllValidatorsSurpassedDelay() external returns (address[] memory addressesCommitted) {
        _requireAdmin();
        uint256 length = _stagedValidatorsAddresses.length();
        addressesCommitted = new address[](length);
        uint256 addressesCommittedLength;
        for (uint256 i; i != length; i++) {
            address stagedAddress = _stagedValidatorsAddresses.at(0);
            if (block.timestamp >= stagedValidatorsTimestamps[stagedAddress]) {
                validators[stagedAddress] = stagedValidators[stagedAddress];
                if (validators[stagedAddress] == address(0)) {
                    _validatorsAddresses.remove(stagedAddress);
                } else {
                    _validatorsAddresses.add(stagedAddress);
                }
                delete stagedValidators[stagedAddress];
                delete stagedValidatorsTimestamps[stagedAddress];
                _stagedValidatorsAddresses.remove(stagedAddress);
                addressesCommitted[addressesCommittedLength] = stagedAddress;
                addressesCommittedLength += 1;
                emit ValidatorCommitted(tx.origin, msg.sender, stagedAddress);
            }
        }
        assembly {
            mstore(addressesCommitted, addressesCommittedLength)
        }
    }

    /// @inheritdoc IProtocolGovernance
    function revokeValidator(address target) external {
        _requireAdmin();
        delete validators[target];
        _validatorsAddresses.remove(target);
        emit ValidatorRevoked(tx.origin, msg.sender, target);
    }

    /// @inheritdoc IProtocolGovernance
    function rollbackAllPermissionGrants() external {
        _requireAdmin();
        uint256 length = _stagedPermissionGrantsAddresses.length();
        for (uint256 i; i != length; ++i) {
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
        if (permissionMasks[stagedAddress] == 0) {
            _permissionAddresses.remove(stagedAddress);
        } else {
            _permissionAddresses.add(stagedAddress);
        }
        delete stagedPermissionGrantsMasks[stagedAddress];
        delete stagedPermissionGrantsTimestamps[stagedAddress];
        _stagedPermissionGrantsAddresses.remove(stagedAddress);
        emit PermissionGrantsCommitted(tx.origin, msg.sender, stagedAddress);
    }

    /// @inheritdoc IProtocolGovernance
    function commitAllPermissionGrantsSurpassedDelay() external {
        _requireAdmin();
        uint256 length = _stagedPermissionGrantsAddresses.length();
        for (uint256 i; i != length; ) {
            address stagedAddress = _stagedPermissionGrantsAddresses.at(i);
            if (block.timestamp >= stagedPermissionGrantsTimestamps[stagedAddress]) {
                permissionMasks[stagedAddress] |= stagedPermissionGrantsMasks[stagedAddress];
                if (permissionMasks[stagedAddress] == 0) {
                    _permissionAddresses.remove(stagedAddress);
                } else {
                    _permissionAddresses.add(stagedAddress);
                }
                delete stagedPermissionGrantsMasks[stagedAddress];
                delete stagedPermissionGrantsTimestamps[stagedAddress];
                _stagedPermissionGrantsAddresses.remove(stagedAddress);
                --length;
                emit PermissionGrantsCommitted(tx.origin, msg.sender, stagedAddress);
            } else {
                ++i;
            }
        }
        // TODO: return an array of addresses that were committed
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
        emit PermissionsRevoked(tx.origin, msg.sender, target, permissionIds);
    }

    /// @inheritdoc IProtocolGovernance
    function commitParams() external {
        _requireAdmin();
        require(pendingParamsTimestamp != 0 && block.timestamp >= pendingParamsTimestamp, ExceptionsLibrary.TIMESTAMP);
        params = pendingParams;
        delete pendingParams;
        delete pendingParamsTimestamp;
        emit PendingParamsCommitted(tx.origin, msg.sender, params);
    }

    /// @inheritdoc IProtocolGovernance
    function stagePermissionGrants(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
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

    // -------------------------  INTERNAL, VIEW  ------------------------------

    function _validateGovernanceParams(IProtocolGovernance.Params calldata newParams) private pure {
        require(newParams.maxTokensPerVault != 0 || newParams.governanceDelay != 0, ExceptionsLibrary.NULL);
        require(newParams.governanceDelay <= MAX_GOVERNANCE_DELAY, ExceptionsLibrary.LIMIT_OVERFLOW);
        require(newParams.withdrawLimit >= MIN_WITHDRAW_LIMIT, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    function _permissionIdsToMask(uint8[] calldata permissionIds) private pure returns (uint256 mask) {
        for (uint256 i = 0; i < permissionIds.length; ++i) {
            mask |= 1 << permissionIds[i];
        }
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when validators are staged to be granted for specific address.
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param target Target address
    /// @param validator Staged validator
    /// @param at Timestamp when the staged permissions could be committed
    event ValidatorStaged(
        address indexed origin,
        address indexed sender,
        address indexed target,
        address validator,
        uint256 at
    );

    /// @notice Validator revoked
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param target Target address
    event ValidatorRevoked(address indexed origin, address indexed sender, address indexed target);

    /// @notice Emitted when staged validators are rolled back
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    event AllStagedValidatorsRolledBack(address indexed origin, address indexed sender);

    /// @notice Emitted when staged validators are comitted for specific address
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param target Target address
    event ValidatorCommitted(address indexed origin, address indexed sender, address indexed target);

    /// @notice Emitted when new permissions are staged to be granted for specific address.
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

    /// @notice Emitted when staged permissions are comitted for specific address
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
