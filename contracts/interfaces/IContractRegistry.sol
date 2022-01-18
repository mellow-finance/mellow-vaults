// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

interface IContractRegistry {
    function addresses() external view returns (address[] memory);
    function names() external view returns (bytes32[] memory);
    function registerContract(address targets) external;
    function latestVersion(bytes32 name) external view returns (bytes32, address);
    function versions(bytes32 name) external view returns (bytes32[] memory result);
}
