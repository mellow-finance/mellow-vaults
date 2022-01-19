// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/utils/IContractMeta.sol";

contract ContractMetaMock is IContractMeta {
    bytes32 public CONTRACT_NAME;
    bytes32 public CONTRACT_VERSION;

    constructor(bytes32 name_, bytes32 version_) {
        CONTRACT_NAME = name_;
        CONTRACT_VERSION = version_;
    }
}
