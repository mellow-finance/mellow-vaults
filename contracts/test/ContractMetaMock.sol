// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

contract ContractMetaMock {
    bytes32 private _contractName;
    bytes32 private _contractVersion;

    constructor(string memory name_, string memory version_) {
        _contractName = bytes32(abi.encodePacked(name_));
        _contractVersion = bytes32(abi.encodePacked(version_));
    }

    function contractName() external view returns (string memory) {
        return _bytes32ToString(_contractName);
    }

    function contractNameBytes() external view returns (bytes32) {
        return _contractName;
    }

    function contractVersion() external view returns (string memory) {
        return _bytes32ToString(_contractVersion);
    }

    function contractVersionBytes() external view returns (bytes32) {
        return _contractVersion;
    }

    function _bytes32ToString(bytes32 b) internal pure returns (string memory s) {
        s = new string(32);
        uint256 len = 32;
        for (uint256 i = 0; i < 32; ++i) {
            if (uint8(b[i]) == 0) {
                len = i;
                break;
            }
        }
        assembly {
            mstore(s, len)
            mstore(add(s, 0x20), b)
        }
    }
}
