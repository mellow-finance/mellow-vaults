// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

contract VersionControl is Ownable {
    mapping(string => string) public latestVersion;

    event VersionChanged(address indexed origin, address indexed sender, string _contractName, string _newVersion);

    constructor() Ownable() {}

    function setLatestVersion(string calldata contractName, string calldata version) external onlyOwner {
        require(_validateVersion(version));
        latestVersion[contractName] = version;
        emit VersionChanged(msg.sender, msg.sender, contractName, version);
    }

    function suspendContractName(string calldata contractName) external onlyOwner {
        latestVersion[contractName] = "suspended";
        emit VersionChanged(msg.sender, msg.sender, contractName, "suspended");
    }

    function _isNumeric(bytes1 num) private pure returns (bool) {
        return (num == "9" ||
            num == "8" ||
            num == "7" ||
            num == "6" ||
            num == "5" ||
            num == "4" ||
            num == "3" ||
            num == "2" ||
            num == "1" ||
            num == "0");
    }

    function _validateVersion(string calldata version) private pure returns (bool) {
        // q0 -- beginning of the number
        // q1 -- in the number
        // q2 -- end of the number
        // q0: [1-9] -> q1, [0] -> q2
        // q1: [0-9] -> q1, '.' -> q0
        // q2: '.' -> q0
        uint8 q;
        uint8 dots;
        bytes memory v = bytes(version);
        for (uint8 i; i != v.length; ++i) {
            if (q == 0) {
                if (_isNumeric(v[i]) && v[i] != "0") {
                    q = 1;
                } else if (v[i] == "0") {
                    q = 2;
                } else {
                    return false;
                }
            } else if (q == 1) {
                if (_isNumeric(v[i])) {
                    q = 1;
                } else if (v[i] == ".") {
                    q = 0;
                    dots++;
                } else {
                    return false;
                }
            } else if (q == 2) {
                if (v[i] == ".") {
                    dots++;
                    q = 0;
                } else {
                    return false;
                }
            }
        }
        return dots == 2 && (q == 1 || q == 2);
    }
}
