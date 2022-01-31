// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/utils/IContractMeta.sol";

abstract contract ContractMeta is IContractMeta {

    // -------------------  EXTERNAL, VIEW  -------------------

    function contractName() external pure returns (string memory) {
        return _bytes32ToString(CONTRACT_NAME());
    }

    function contractNameBytes() external pure returns (bytes32) {
        return CONTRACT_NAME();
    }

    function contractVersion() external pure returns (string memory) {
        return _bytes32ToString(CONTRACT_VERSION());
    }

    function contractVersionBytes() external pure returns (bytes32) {
        return CONTRACT_VERSION();
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function CONTRACT_NAME() internal pure virtual returns (bytes32);

    function CONTRACT_VERSION() internal pure virtual returns (bytes32);

    function _bytes32ToString(bytes32 b) internal pure returns (string memory s) {
        s = new string(32);
        uint256 len = 32;
        for (uint i = 0; i < 32; ++i) {
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
