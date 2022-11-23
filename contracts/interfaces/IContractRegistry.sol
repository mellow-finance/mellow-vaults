// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IContractRegistry {
    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Addresses of the registered contracts
    function addresses() external view returns (address[] memory);

    /// @notice Names of the registered contracts
    function names() external view returns (string[] memory);

    /// @notice Latest version of the contract
    /// @param name Name of the contract
    function latestVersion(string memory name) external view returns (string memory, address);

    /// @notice All versions of the contract
    /// @param name Name of the contract
    function versions(string memory name) external view returns (string[] memory result);

    /// @notice Address of the contract at a given version
    /// @param name Name of the contract
    /// @param version Version of the contract
    function versionAddress(string memory name, string memory version) external view returns (address);

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Register a new contract
    /// @param target Address of the contract to be registered
    function registerContract(address target) external;
}
