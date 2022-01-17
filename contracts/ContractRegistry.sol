// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/utils/IContractRegistry.sol";
import "./interfaces/utils/IContractMeta.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./libraries/PermissionIdsLibrary.sol";

contract ContractRegistry is IContractRegistry, Multicall {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    IProtocolGovernance public governance;
    mapping(bytes32 => address[]) public registeredContractsAddresses;
    mapping(bytes32 => uint256) public versionCount;

    EnumerableSet.AddressSet private _registeredContracts;
    EnumerableSet.AddressSet private _taggedAddresses;
    mapping(address => EnumerableSet.Bytes32Set) private _tags;

    constructor(address _governance) {
        governance = IProtocolGovernance(_governance);
    }

    function tagAddresses() external view returns (address[] memory) {
        return _taggedAddresses.values();
    }

    function tags(address target) external view returns (bytes32[] memory) {
        EnumerableSet.Bytes32Set storage tagsRef = _tags[target];
        return tagsRef.values();
    }

    function registeredContracts() external view returns (address[] memory) {
        return _registeredContracts.values();
    }

    function registerContracts(address[] calldata targets) external {
        require(
            governance.hasPermission(msg.sender, PermissionIdsLibrary.TRUSTED_DEPLOYER),
            ExceptionsLibrary.FORBIDDEN
        );
        for (uint256 i; i != targets.length; ++i) {
            require(_registeredContracts.add(targets[i]), ExceptionsLibrary.DUPLICATE);
            IContractMeta newContract = IContractMeta(targets[i]);
            bytes32 newContractName = newContract.CONTRACT_NAME();
            uint256 newContractVersion = newContract.CONTRACT_VERSION();
            registeredContractsAddresses[newContractName].push(targets[i]);
            uint256 currentVersionCount = versionCount[newContractName];
            require(currentVersionCount + 1 >= newContractVersion, ExceptionsLibrary.INVALID_VALUE);
            if (newContractVersion > currentVersionCount) {
                ++versionCount[newContractName];
            }
        }
    }

    function addTag(address to, bytes32 tag) external {
        _requireTagManager();
        _tags[to].add(tag);
        _taggedAddresses.add(to);
    }

    function removeTag(address from, bytes32 tag) external {
        _requireTagManager();
        EnumerableSet.Bytes32Set storage tagsRef = _tags[from];
        tagsRef.remove(tag);
        if (tagsRef.length() == 0) {
            _taggedAddresses.remove(from);
        }
    }

    function _requireTagManager() internal view {
        require(governance.hasPermission(msg.sender, PermissionIdsLibrary.TAG_MANAGER), ExceptionsLibrary.FORBIDDEN);
    }
}
