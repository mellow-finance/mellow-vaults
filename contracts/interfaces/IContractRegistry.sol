// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

interface IContractRegistry {
    function addresses() external view returns (address[] memory);

    function names() external view returns (string[] memory);

    function registerContract(address targets) external;

    function latestVersion(string memory name) external view returns (string memory, address);

    function versions(string memory name) external view returns (string[] memory result);
}
