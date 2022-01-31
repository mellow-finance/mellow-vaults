// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../utils/ContractMeta.sol";

contract ContractMetaMock is ContractMeta {
    bytes32 private _inputContractName;
    bytes32 private _inputContractVersion;

    constructor(string memory name_, string memory version_) {
        _inputContractName = bytes32(abi.encodePacked(name_));
        _inputContractVersion = bytes32(abi.encodePacked(version_));
    }

    function _contractName() internal pure override returns (bytes32) {
//        return _contractName;
        return bytes32("mock");
    }

    function _contractVersion() internal pure override returns (bytes32) {
//        return __contractVersion;
        return bytes32("mock");
    }
}
