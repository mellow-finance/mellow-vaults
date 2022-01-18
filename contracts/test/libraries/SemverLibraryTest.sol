// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../../libraries/SemverLibrary.sol";

contract SemverLibraryTest {
    function stringify(uint256 input) external pure returns (bytes memory) {
        return SemverLibrary.stringify(input);
    }

    function numberify(bytes memory input) external pure returns (uint256) {
        return SemverLibrary.numberify(input);
    }

    function stringifySemver(uint256 input) external pure returns (bytes32) {
        return SemverLibrary.stringifySemver(input);
    }

    function numberifySemver(bytes32 input) external pure returns (uint256) {
        return SemverLibrary.numberifySemver(input);
    }
}
