// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./UnitPricesGovernance.sol";
import "./utils/ContractMeta.sol";

/// @notice Governance that manages all params common for Mellow Permissionless Vaults protocol.
contract ProtocolGovernance is ContractMeta, IProtocolGovernance, ERC165, UnitPricesGovernance, Multicall {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant MAX_GOVERNANCE_DELAY = 7 days;
    uint256 public constant MIN_WITHDRAW_LIMIT = 200_000;

    /// @inheritdoc IProtocolGovernance
    mapping(address => uint256) public stagedPermissionGrantsTimestamps;
    /// @inheritdoc IProtocolGovernance
    mapping(address => uint256) public stagedPermissionGrantsMasks;
    /// @inheritdoc IProtocolGovernance
    mapping(address => uint256) public permissionMasks;

    /// @inheritdoc IProtocolGovernance
    mapping(address => uint256) public stagedValidatorsTimestamps;
    /// @inheritdoc IProtocolGovernance
    mapping(address => address) public stagedValidators;
    /// @inheritdoc IProtocolGovernance
    mapping(address => address) public validators;

    /// @inheritdoc IProtocolGovernance
    uint256 public stagedParamsTimestamp;

    EnumerableSet.AddressSet private _stagedPermissionGrantsAddresses;
    EnumerableSet.AddressSet private _permissionAddresses;
    EnumerableSet.AddressSet private _validatorsAddresses;
    EnumerableSet.AddressSet private _stagedValidatorsAddresses;

    Params private _stagedParams;
    Params private _params;

    /// @notice Creates a new contract
    /// @param admin Initial admin of the contract
    constructor(address admin) UnitPricesGovernance(admin) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IProtocolGovernance
    function stagedParams() public view returns (Params memory) {
        return _stagedParams;
    }

    /// @inheritdoc IProtocolGovernance
    function params() public view returns (Params memory) {
        return _params;
    }

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
        addresses = new address[](length);
        uint256 addressesLength = 0;
        uint256 mask = 1 << permissionId;
        for (uint256 i = 0; i < length; i++) {
            address addr = _permissionAddresses.at(i);
            if (permissionMasks[addr] & mask != 0) {
                addresses[addressesLength] = addr;
                addressesLength++;
            }
        }
        // shrink to fit
        assembly {
            mstore(addresses, addressesLength)
        }
    }

    /// @inheritdoc IProtocolGovernance
    function hasPermission(address target, uint8 permissionId) external view returns (bool) {
        return ((permissionMasks[target] | _params.forceAllowMask) & (1 << (permissionId))) != 0;
    }

    /// @inheritdoc IProtocolGovernance
    function hasAllPermissions(address target, uint8[] calldata permissionIds) external view returns (bool) {
        uint256 submask = _permissionIdsToMask(permissionIds);
        uint256 mask = permissionMasks[target] | _params.forceAllowMask;
        return mask & submask == submask;
    }

    /// @inheritdoc IProtocolGovernance
    function maxTokensPerVault() external view returns (uint256) {
        return _params.maxTokensPerVault;
    }

    /// @inheritdoc IProtocolGovernance
    function governanceDelay() external view returns (uint256) {
        return _params.governanceDelay;
    }

    /// @inheritdoc IProtocolGovernance
    function protocolTreasury() external view returns (address) {
        return _params.protocolTreasury;
    }

    /// @inheritdoc IProtocolGovernance
    function forceAllowMask() external view returns (uint256) {
        return _params.forceAllowMask;
    }

    /// @inheritdoc IProtocolGovernance
    function withdrawLimit(address token) external view returns (uint256) {
        return _params.withdrawLimit * unitPrices[token];
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
        require(
            target != address(0) &&
            validator != address(0), 
            ExceptionsLibrary.ADDRESS_ZERO
        );
        _stagedValidatorsAddresses.add(target);
        stagedValidators[target] = validator;
        uint256 at = block.timestamp + _params.governanceDelay;
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
        _validatorsAddresses.add(stagedAddress);
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
        for (uint256 i; i != length;) {
            address stagedAddress = _stagedValidatorsAddresses.at(i);
            if (block.timestamp >= stagedValidatorsTimestamps[stagedAddress]) {
                validators[stagedAddress] = stagedValidators[stagedAddress];
                _validatorsAddresses.add(stagedAddress);
                delete stagedValidators[stagedAddress];
                delete stagedValidatorsTimestamps[stagedAddress];
                _stagedValidatorsAddresses.remove(stagedAddress);
                addressesCommitted[addressesCommittedLength] = stagedAddress;
                ++addressesCommittedLength;
                --length;
                emit ValidatorCommitted(tx.origin, msg.sender, stagedAddress);
            } else {
                ++i;
            }
        }
        assembly {
            mstore(addressesCommitted, addressesCommittedLength)
        }
    }

    /// @inheritdoc IProtocolGovernance
    function revokeValidator(address target) external {
        _requireAdmin();
        require(target != address(0), ExceptionsLibrary.NULL);
        delete validators[target];
        _validatorsAddresses.remove(target);
        emit ValidatorRevoked(tx.origin, msg.sender, target);
    }

    /// @inheritdoc IProtocolGovernance
    function rollbackStagedPermissionGrants() external {
        _requireAdmin();
        uint256 length = _stagedPermissionGrantsAddresses.length();
        for (uint256 i; i != length; ++i) {
            address target = _stagedPermissionGrantsAddresses.at(0);
            delete stagedPermissionGrantsMasks[target];
            delete stagedPermissionGrantsTimestamps[target];
            _stagedPermissionGrantsAddresses.remove(target);
        }
        emit AllStagedPermissionGrantsRolledBack(tx.origin, msg.sender);
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
    function commitAllPermissionGrantsSurpassedDelay() external returns (address[] memory addresses) {
        _requireAdmin();
        uint256 length = _stagedPermissionGrantsAddresses.length();
        uint256 addressesLeft = length;
        addresses = new address[](length);
        for (uint256 i; i != addressesLeft;) {
            address stagedAddress = _stagedPermissionGrantsAddresses.at(i);
            if (block.timestamp >= stagedPermissionGrantsTimestamps[stagedAddress]) {
                permissionMasks[stagedAddress] |= stagedPermissionGrantsMasks[stagedAddress];
                _permissionAddresses.add(stagedAddress);
                delete stagedPermissionGrantsMasks[stagedAddress];
                delete stagedPermissionGrantsTimestamps[stagedAddress];
                _stagedPermissionGrantsAddresses.remove(stagedAddress);
                addresses[length - addressesLeft] = stagedAddress;
                --addressesLeft;
                emit PermissionGrantsCommitted(tx.origin, msg.sender, stagedAddress);
            } else {
                ++i;
            }
        }
        length -= addressesLeft;
        assembly {
            mstore(addresses, length)
        }
    }

    /// @inheritdoc IProtocolGovernance
    function revokePermissions(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
        require(target != address(0), ExceptionsLibrary.NULL);
        uint256 diff = _permissionIdsToMask(permissionIds);
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
        require(stagedParamsTimestamp != 0, ExceptionsLibrary.NULL);
        require(
            block.timestamp >= stagedParamsTimestamp,
            ExceptionsLibrary.TIMESTAMP
        );
        _params = _stagedParams;
        delete _stagedParams;
        delete stagedParamsTimestamp;
        emit ParamsCommitted(tx.origin, msg.sender, _params);
    }

    /// @inheritdoc IProtocolGovernance
    function stagePermissionGrants(address target, uint8[] calldata permissionIds) external {
        _requireAdmin();
        require(target != address(0), ExceptionsLibrary.NULL);
        _stagedPermissionGrantsAddresses.add(target);
        stagedPermissionGrantsMasks[target] = _permissionIdsToMask(permissionIds);
        uint256 stagedToCommitAt = block.timestamp + _params.governanceDelay;
        stagedPermissionGrantsTimestamps[target] = stagedToCommitAt;
        emit PermissionGrantsStaged(tx.origin, msg.sender, target, permissionIds, stagedToCommitAt);
    }

    /// @inheritdoc IProtocolGovernance
    function stageParams(IProtocolGovernance.Params calldata newParams) external {
        _requireAdmin();
        _validateGovernanceParams(newParams);
        _stagedParams = newParams;
        stagedParamsTimestamp = block.timestamp + _params.governanceDelay;
        emit ParamsStaged(tx.origin, msg.sender, stagedParamsTimestamp, _stagedParams);
    }

    // -------------------------  INTERNAL, VIEW  ------------------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("ProtocolGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    function _validateGovernanceParams(IProtocolGovernance.Params calldata newParams) private pure {
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
    event AllStagedPermissionGrantsRolledBack(address indexed origin, address indexed sender);

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
    event ParamsStaged(address indexed origin, address indexed sender, uint256 at, Params params);

    /// @notice Emitted when pending parameters are committed
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param params Committed parameters
    event ParamsCommitted(address indexed origin, address indexed sender, Params params);
}
