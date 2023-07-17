// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../libraries/SemverLibrary.sol";

contract SemverLibraryTest {
    function stringifySemver(uint256 input) external pure returns (string memory) {
        return SemverLibrary.stringifySemver(input);
    }

    function numberifySemver(string memory input) external pure returns (uint256) {
        return SemverLibrary.numberifySemver(input);
    }
}
