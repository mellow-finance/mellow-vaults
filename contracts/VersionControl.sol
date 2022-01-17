// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

contract VersionControl is Ownable {
    mapping(string => string) public latestVersion;

    event VersionChanged(address indexed origin, address indexed sender, string _contractName, string _newVersion);

    constructor() Ownable() {}

    function setLatestVersion(string calldata contractName, string calldata version) external onlyOwner {
        latestVersion[contractName] = version;
        emit VersionChanged(msg.sender, msg.sender, contractName, version);
    }
}
