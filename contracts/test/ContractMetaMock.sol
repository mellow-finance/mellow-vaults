// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/utils/IContractMeta.sol";

contract ContractMetaMock is IContractMeta {
    bytes32 public CONTRACT_NAME;
    bytes32 public CONTRACT_VERSION;

    constructor(string memory name_, string memory version_) {
        CONTRACT_NAME = bytes32(abi.encodePacked(name_));
        CONTRACT_VERSION = bytes32(abi.encodePacked(version_));
    }
}
