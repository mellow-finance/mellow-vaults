// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/ContractMeta.sol";

contract ContractMetaMock is ContractMeta {
    bytes32 private _contractName;
    bytes32 private _contractVersion;

    constructor(string memory name_, string memory version_) {
        _contractName = bytes32(abi.encodePacked(name_));
        _contractVersion = bytes32(abi.encodePacked(version_));
    }

    function CONTRACT_NAME() internal pure override returns (bytes32) {
//        return _contractName;
        return bytes32("mock");
    }

    function CONTRACT_VERSION() internal pure override returns (bytes32) {
//        return _contractVersion;
        return bytes32("mock");
    }
}
