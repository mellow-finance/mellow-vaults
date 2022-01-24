// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

library SemverLibrary {
    uint8 internal constant ASCII_ZERO = 48;
    uint8 internal constant BIT_OFFSET = 85;
    uint256 internal constant MAX_LENGTH = 0x1f;

    function isNumeric(bytes1 num) internal pure returns (bool) {
        return num >= "0" && num <= "9";
    }

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

    function numberify(bytes memory _num) internal pure returns (uint256 result) {
        for (uint256 i; i != _num.length; ++i) {
            result *= 10;
            result += uint256(uint8(_num[i])) - ASCII_ZERO;
        }
    }

    function stringify(uint256 num) internal pure returns (bytes memory result) {
        if (num == 0) {
            return "0";
        }
        uint256 i;
        bytes memory resultTemp = new bytes(0xff);
        while (num > 0) {
            uint256 digit = num % 10;
            resultTemp[i] = bytes1(uint8(digit) + ASCII_ZERO);
            num /= 10;
            ++i;
        }
        result = new bytes(i);
        for (uint256 j; j != i; ++j) {
            result[j] = resultTemp[i - j - 1];
        }
    }

    function numberifySemver(string memory _semver) internal pure returns (uint256) {
        uint256[3] memory res;
        uint256 semveri;
        for (uint256 i = 0; (i < bytes(_semver).length) && semveri < 3; i++) {
            uint8 b = uint8(bytes(_semver)[i]);
            if (b == uint8(bytes1("."))) {
                semveri += 1;
                continue;
            }
            if (b < ASCII_ZERO || b > ASCII_ZERO + 9) {
                return 0;
            }
            res[semveri] = res[semveri] * 10 + b - ASCII_ZERO;
        }
        if (semveri != 3) {
            return 0;
        }
        return (res[0] << (16 + res[1])) << (8 + res[2]);
        // bytes memory semver = bytes(_semver);

        // uint8 BEFORE_NUMBER = 0;
        // uint8 IN_NUMBER = 1;
        // uint8 END_OF_NUMBER = 2;

        // uint8 state;
        // uint8 dotsCount;
        // uint8 lastDotPosition;

        // bytes memory num1 = new bytes(MAX_LENGTH);
        // bytes memory num2 = new bytes(MAX_LENGTH);
        // bytes memory num3 = new bytes(MAX_LENGTH);

        // for (uint8 i; i != semver.length; ++i) {
        //     // switch state

        //     // q0: [1-9] -> q1, [0] -> q2
        //     if (state == BEFORE_NUMBER) {
        //         if (isNumeric(semver[i]) && semver[i] != "0") {
        //             state = IN_NUMBER;
        //         } else if (semver[i] == "0") {
        //             state = END_OF_NUMBER;
        //         } else {
        //             return 0;
        //         }
        //         // q1: [0-9] -> q1, '.' -> q0
        //     } else if (state == IN_NUMBER) {
        //         if (isNumeric(semver[i])) {
        //             state = IN_NUMBER;
        //         } else if (semver[i] == ".") {
        //             dotsCount++;
        //             lastDotPosition = i;
        //             state = BEFORE_NUMBER;
        //         } else {
        //             return 0;
        //         }
        //         // q2: '.' -> q0
        //     } else if (state == END_OF_NUMBER) {
        //         if (semver[i] == ".") {
        //             dotsCount++;
        //             lastDotPosition = i;
        //             state = BEFORE_NUMBER;
        //         } else {
        //             return 0;
        //         }
        //     }

        //     // construct the number

        //     if (dotsCount > 2) {
        //         return 0;
        //     }

        //     if (state != BEFORE_NUMBER) {
        //         if (dotsCount == 0) {
        //             num1[i] = semver[i];
        //         } else if (dotsCount == 1) {
        //             num2[i - lastDotPosition - 1] = semver[i];
        //         } else {
        //             num3[i - lastDotPosition - 1] = semver[i];
        //         }
        //     }
        // }
        // if (dotsCount == 2 && state != BEFORE_NUMBER) {
        //     uint256 result = numberify(shrinkToFit(num1)) << BIT_OFFSET;
        //     result |= numberify(shrinkToFit(num2));
        //     result <<= BIT_OFFSET;
        //     result |= numberify(shrinkToFit(num3));
        //     return result;
        // }
        // return 0;
    }

    function stringifySemver(uint256 num) internal pure returns (string memory) {
        uint256 filterMask = (1 << BIT_OFFSET) - 1;
        bytes memory n1 = stringify(num >> (BIT_OFFSET * 2));
        bytes memory n2 = stringify((num >> BIT_OFFSET) & filterMask);
        bytes memory n3 = stringify(num & filterMask);
        bytes memory result = new bytes(n1.length + n2.length + n3.length + 2);
        for (uint256 i; i != n1.length; ++i) {
            result[i] = n1[i];
        }
        result[n1.length] = ".";
        for (uint256 i; i != n2.length; ++i) {
            result[n1.length + 1 + i] = n2[i];
        }
        result[n1.length + n2.length + 1] = ".";
        for (uint256 i; i != n3.length; ++i) {
            result[n1.length + n2.length + 2 + i] = n3[i];
        }
        return string(result);
    }
}
