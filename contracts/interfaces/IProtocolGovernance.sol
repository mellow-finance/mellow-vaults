// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./utils/IDefaultAccessControl.sol";

interface IProtocolGovernance is IDefaultAccessControl {
    /// @notice CommonLibrary protocol params.
    /// @param permissionless If `true` anyone can spawn vaults, o/w only Protocol Governance Admin
    /// @param maxTokensPerVault Max different token addresses that could be managed by the protocol
    /// @param governanceDelay The delay (in secs) that must pass before setting new pending params to commiting them
    /// @param protocolTreasury Protocol treasury address for collecting management fees
    struct Params {
        uint256 maxTokensPerVault;
        uint256 governanceDelay;
        address protocolTreasury;
        bool permissionless;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Checks if address has permission
    /// @param addr Address to check
    /// @param permissionId Permission id to check
    function hasPermission(address addr, uint8 permissionId) external view returns (bool);

    /// @notice Returns known addresses
    function addresses() external view returns (address[] memory);

    /// @notice Returns number of known addresses
    function addressesLength() external view returns (uint256);

    /// @notice Returns address by index
    function addressAt(uint256 index) external view returns (address);

    /// @notice Returns a bit mask of permissions for an address
    /// @param addr Address to check
    function permissionMask(address addr) external view returns (uint256);

    /// @notice Returns staged addresses
    function stagedAddresses() external view returns (address[] memory);

    /// @notice Returns number of staged addresses
    function stagedAddressesLength() external view returns (uint256);

    /// @notice Returns staged address by index
    function stagedAddressAt(uint256 index) external view returns (address);

    /// @notice Returns a bit mask of permissions for a staged address
    function stagedPermissionMask(address addr) external view returns (uint256);

    /// @notice Checks if address has all permissions
    /// @param target Address to check
    /// @param permissionIds A list of permission ids to check
    function hasAllPermissions(address target, uint8[] calldata permissionIds) external view returns (bool);

    /// @notice Checks if address has permission staged
    /// @param addr Address to check
    /// @param permissionId Permission id to check
    function hasStagedPermission(address addr, uint8 permissionId) external view returns (bool);

    /// @notice Checks if address has all given permissions staged
    /// @param addr Address to check
    /// @param permissionIds A list of permission ids to check
    function hasStagedAllPermissions(address addr, uint8[] memory permissionIds) external view returns (bool);

    /// @notice Returns timestamp of the upcoming commit if staged, else returns 0
    function stagedToCommitAt() external view returns (uint256);

    /// @notice If `false` only admins can deploy new vaults, o/w anyone can deploy a new vault.
    function permissionless() external view returns (bool);

    /// @notice Max different ERC20 token addresses that could be managed by the protocol.
    function maxTokensPerVault() external view returns (uint256);

    /// @notice The delay for committing any governance params.
    function governanceDelay() external view returns (uint256);

    /// @notice The address of the protocol treasury.
    function protocolTreasury() external view returns (address);

    // -------------------  EXTERNAL, MUTATING, GOVERNANCE, DELAY  -------------------

    /// @notice Set new pending params.
    /// @param newParams newParams to set
    function setPendingParams(Params memory newParams) external;

    /// @notice Stage pending permissions.
    /// @param target Target address
    /// @param permissionIds A list of permission ids to grant
    function stageGrantPermissions(address target, uint8[] memory permissionIds) external;

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------

    /// @notice Rollback staged permissions.
    function rollbackStagedPermissions() external;

    /// @notice Commit staged permissions.
    function commitStagedPermissions() external;

    /// @notice Revoke permission instant.
    /// @param target Target address
    /// @param permissionIds A list of permission ids to revoke
    function revokePermissionsInstant(address target, uint8[] memory permissionIds) external;

    /// @notice Commit pending params.
    function commitParams() external;
}
