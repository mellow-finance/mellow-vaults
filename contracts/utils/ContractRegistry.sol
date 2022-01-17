// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IProtocolGovernance.sol";
import "../interfaces/utils/IContractRegistry.sol";
import "../interfaces/utils/IContractMeta.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/PermissionIdsLibrary.sol";

contract ContractRegistry is IContractRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;
    IProtocolGovernance public governance;
    mapping(bytes32 => address[]) public registeredContractsAddresses;
    mapping(bytes32 => uint256) public versionCount;
    EnumerableSet.AddressSet private _registeredContracts;

    constructor(address _governance) {
        governance = IProtocolGovernance(_governance);
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
            bytes32 newContractName = newContract.CONRTACT_NAME();
            uint256 newContractVersion = newContract.CONTRACT_VERSION();
            registeredContractsAddresses[newContractName].push(targets[i]);
            uint256 currentVersionCount = versionCount[newContractName];
            require(currentVersionCount + 1 >= newContractVersion, ExceptionsLibrary.INVALID_VALUE);
            if (newContractVersion > currentVersionCount) {
                ++versionCount[newContractName];
            }
        }
    }
}
