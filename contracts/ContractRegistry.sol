// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IContractRegistry.sol";
import "./interfaces/utils/IContractMeta.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./libraries/SemverLibrary.sol";

contract ContractRegistry is IContractMeta, IContractRegistry, Multicall {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 public CONTRACT_NAME = "ContractRegistry";
    bytes32 public CONTRACT_VERSION = "1.0.0";

    IProtocolGovernance public governance;

    mapping(bytes32 => mapping(uint256 => address)) private _nameToVersionToAddress;
    mapping(bytes32 => uint256[]) private _nameToVersions;
    EnumerableSet.AddressSet private _addresses;
    EnumerableSet.Bytes32Set private _names;

    constructor(address _governance) {
        governance = IProtocolGovernance(_governance);
    }

    function addresses() external view returns (address[] memory) {
        return _addresses.values();
    }

    function names() external view returns (bytes32[] memory) {
        return _names.values();
    }

    function versions(bytes32 name) external view returns (bytes32[] memory result) {
        uint256[] memory versions_ = _nameToVersions[name];
        result = new bytes32[](versions_.length);
        for (uint256 i = 0; i < versions_.length; i++) {
            result[i] = SemverLibrary.stringifySemver(versions_[i]);
        }
    }

    function versionAddress(bytes32 name, bytes32 version) external view returns (address) {
        uint256 versionNum = SemverLibrary.numberifySemver(version);
        return _nameToVersionToAddress[name][versionNum];
    }

    function latestVersion(bytes32 name) external view returns (bytes32, address) {
        uint256 version = _latestVersion(name);
        return (
            SemverLibrary.stringifySemver(version),
            _nameToVersionToAddress[name][version]
        );
    }

    function registerContract(address target) external {
        require(governance.isOperator(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(
            _addresses.add(target),
            ExceptionsLibrary.DUPLICATE
        );

        IContractMeta newContract = IContractMeta(target);
        bytes32 newContractName = newContract.CONTRACT_NAME();
        bytes32 newContractVersionRaw = newContract.CONTRACT_VERSION();
        uint256 newContractVersion = SemverLibrary.numberifySemver(newContractVersionRaw);

        require(
            _validateContractName(newContractName) && newContractName != CONTRACT_NAME,
            ExceptionsLibrary.INVALID_VALUE
        );
        require(
            newContractVersion > _latestVersion(newContractName),
            ExceptionsLibrary.INVARIANT
        );

        _nameToVersionToAddress[newContractName][newContractVersion] = target;
        _nameToVersions[newContractName].push(newContractVersion);
        _names.add(newContractName);

        emit ContractRegistered(
            tx.origin,
            msg.sender,
            newContractName,
            newContractVersionRaw,
            target
        );
    }

    function _latestVersion(bytes32 name) internal view returns (uint256) {
        uint256 versionsLength = _nameToVersions[name].length;
        return versionsLength != 0 ? _nameToVersions[name][versionsLength - 1] : 0;
    }

    function _validateContractName(bytes32 name_) internal pure returns (bool) {
        bytes memory name = SemverLibrary.shrinkToFit(abi.encodePacked(name_));
        for (uint256 i; i < name.length; ++i) {
            uint8 ascii = uint8(name[i]);
            bool isAlphanumeric = (
                (0x61 <= ascii && ascii <= 0x7a) || 
                (0x41 <= ascii && ascii <= 0x5a) || 
                (0x30 <= ascii && ascii <= 0x39)
            );
            if (!isAlphanumeric) {
                return false;
            }
        }
        return true;
    }

    event ContractRegistered(
        address indexed origin,
        address indexed sender,
        bytes32 indexed name,
        bytes32 version, 
        address target
    );
}
