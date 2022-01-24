// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Strings.sol";

library SemverLibrary {
    uint8 internal constant ASCII_ZERO = 48;

    function shrinkToFit(bytes memory array) internal pure returns (bytes memory result) {
        uint256 i;
        while (i != array.length && array[i] != 0) {
            ++i;
        }
        result = new bytes(i);
        for (uint256 j; j != i; ++j) {
            result[j] = array[j];
        }
    }

    function numberifySemver(string memory _semver) internal pure returns (uint256) {
        uint256[3] memory res;
        uint256 semverIndex;
        uint256 semverLength;
        for (uint256 i = 0; (i < bytes(_semver).length) && (semverIndex < 3); i++) {
            uint8 b = uint8(bytes(_semver)[i]);
            if (b == uint8(bytes1("."))) {
                // forbid empty semver part
                if (semverLength == 0) {
                    return 0;
                }
                semverIndex += 1;
                semverLength = 0;
                continue;
            }
            if (b < ASCII_ZERO || b > ASCII_ZERO + 9) {
                return 0;
            }
            res[semverIndex] = res[semverIndex] * 10 + b - ASCII_ZERO;
            semverLength += 1;
        }
        if ((semverIndex != 2) || (semverLength == 0)) {
            return 0;
        }
        return (res[0] << 16) + (res[1] << 8) + res[2];
    }

    function stringifySemver(uint256 num) internal pure returns (string memory) {
        if (num >= 1 << 24) {
            return "0";
        }
        string memory major = Strings.toString(num >> 16);
        string memory minor = Strings.toString((num >> 8) & 0xff);
        string memory patch = Strings.toString(num & 0xff);
        return string(abi.encodePacked(abi.encodePacked(major, ".", minor, ".", patch)));
    }
}
