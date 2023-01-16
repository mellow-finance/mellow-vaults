// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IContractRegistry.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./libraries/SemverLibrary.sol";
import "./utils/ContractMeta.sol";

contract ContractRegistry is ContractMeta, IContractRegistry, Multicall {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    IProtocolGovernance public governance;

    mapping(bytes32 => mapping(uint256 => address)) private _nameToVersionToAddress;
    mapping(bytes32 => uint256[]) private _nameToVersions;
    EnumerableSet.AddressSet private _addresses;
    EnumerableSet.Bytes32Set private _names;

    constructor(address _governance) {
        governance = IProtocolGovernance(_governance);
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IContractRegistry
    function addresses() external view returns (address[] memory) {
        return _addresses.values();
    }

    /// @inheritdoc IContractRegistry
    function names() external view returns (string[] memory result) {
        uint256 length = _names.length();
        result = new string[](length);
        for (uint256 i; i != length; ++i) {
            result[i] = _bytes32ToString(_names.at(i));
        }
    }

    /// @inheritdoc IContractRegistry
    function versions(string memory name_) external view returns (string[] memory result) {
        bytes32 name = bytes32(bytes(name_));
        uint256[] memory versions_ = _nameToVersions[name];
        result = new string[](versions_.length);
        for (uint256 i = 0; i < versions_.length; i++) {
            result[i] = SemverLibrary.stringifySemver(versions_[i]);
        }
    }

    /// @inheritdoc IContractRegistry
    function versionAddress(string memory name_, string memory version) external view returns (address) {
        bytes32 name = bytes32(bytes(name_));
        uint256 versionNum = SemverLibrary.numberifySemver(version);
        return _nameToVersionToAddress[name][versionNum];
    }

    /// @inheritdoc IContractRegistry
    function latestVersion(string memory name_) external view returns (string memory, address) {
        bytes32 name = bytes32(abi.encodePacked(name_));
        uint256 version = _latestVersion(name);
        return (string(SemverLibrary.stringifySemver(version)), _nameToVersionToAddress[name][version]);
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IContractRegistry
    function registerContract(address target) external {
        _requireAtLeastOperator();
        require(_addresses.add(target), ExceptionsLibrary.DUPLICATE);

        IContractMeta newContract = IContractMeta(target);
        bytes32 newContractName = newContract.contractNameBytes();
        require(_validateContractName(newContractName), ExceptionsLibrary.INVALID_VALUE);

        bytes32 newContractVersionRaw = newContract.contractVersionBytes();
        uint256 newContractVersion = SemverLibrary.numberifySemver(newContract.contractVersion());
        uint256 latestContractVersion = _latestVersion(newContractName);

        require(newContractVersion > latestContractVersion, ExceptionsLibrary.INVARIANT);

        uint256 newContractVersionMajor = newContractVersion >> 16;
        uint256 latestContractVersionMajor = latestContractVersion >> 16;
        require(newContractVersionMajor - latestContractVersionMajor <= 1, ExceptionsLibrary.INVARIANT);

        _nameToVersionToAddress[newContractName][newContractVersion] = target;
        _nameToVersions[newContractName].push(newContractVersion);
        _names.add(newContractName);

        emit ContractRegistered(tx.origin, msg.sender, newContractName, newContractVersionRaw, target);
    }

    // -------------------------  INTERNAL, VIEW  ------------------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("ContractRegistry");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    function _requireAtLeastOperator() private view {
        require(
            governance.isOperator(msg.sender) || governance.isAdmin(msg.sender), 
            ExceptionsLibrary.FORBIDDEN
        );
    }

    function _latestVersion(bytes32 name) private view returns (uint256) {
        uint256 versionsLength = _nameToVersions[name].length;
        return versionsLength != 0 ? _nameToVersions[name][versionsLength - 1] : 0;
    }

    function _validateContractName(bytes32 name_) private pure returns (bool) {
        bytes memory name = bytes(_bytes32ToString(name_));
        for (uint256 i; i < name.length; ++i) {
            uint8 ascii = uint8(name[i]);
            bool isAlphanumeric = ((0x61 <= ascii && ascii <= 0x7a) ||
                (0x41 <= ascii && ascii <= 0x5a) ||
                (0x30 <= ascii && ascii <= 0x39));
            if (!isAlphanumeric) {
                return false;
            }
        }
        return true;
    }

    // --------------------------  EVENTS  --------------------------

    event ContractRegistered(
        address indexed origin,
        address indexed sender,
        bytes32 indexed name,
        bytes32 version,
        address target
    );
}
