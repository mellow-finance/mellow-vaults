// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/utils/IContractMeta.sol";

contract ContractMetaMock is IContractMeta {
    bytes32 public CONTRACT_NAME;
    bytes32 public CONTRACT_VERSION;

    function setName(bytes32 newName) external {
        CONTRACT_NAME = newName;
    }

    function setVersion(bytes32 newVersion) external {
        CONTRACT_VERSION = newVersion;
    }
}
