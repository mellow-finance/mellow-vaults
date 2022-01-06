// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./utils/IDefaultAccessControl.sol";

interface IProtocolGovernance is IDefaultAccessControl {
    /// @notice CommonLibrary protocol params.
    /// @param permissionless If `true` anyone can spawn vaults, o/w only Protocol Governance Admin
    /// @param maxTokensPerVault Max different token addresses that could be managed by the protocol
    /// @param governanceDelay The delay (in secs) that must pass before setting new pending params to commiting them
    /// @param allowDenyMask Permissions mask which defines if ordinary permission should be reverted. This bitmask is xored with ordinary mask.
    struct Params {
        uint256 maxTokensPerVault;
        uint256 governanceDelay;
        address protocolTreasury;
        uint256 allowDenyMask;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Checks if address has permission.
    /// @param addr Address to check
    /// @param permissionId Permission id to check
    function hasPermission(address addr, uint8 permissionId) external view returns (bool);

    /// @notice Checks if address has all permissions.
    /// @param target Address to check
    /// @param permissionIds A list of permission ids to check
    function hasAllPermissions(address target, uint8[] calldata permissionIds) external view returns (bool);

    /// @notice Addresses for which non-zero permissions are set.
    function permissionAddresses() external view returns (address[] memory);

    /// @notice Number of addresses for which non-zero permissions are set.
    function permissionAddressesCount() external view returns (uint256);

    /// @notice Address at a specific index for which non-zero permissions are set.
    /// @param index Number of a permission address
    /// @return Permission address
    function permissionAddressAt(uint256 index) external view returns (address);

    /// @notice Raw bitmask of permissions for an address (allowDenyMask is not applied).
    /// @param addr Address to check
    /// @return A bitmask of permissions for an address
    function rawPermissionMask(address addr) external view returns (uint256);

    /// @notice Bitmask of true permissions for an address (allowDenyMask is applied).
    /// @param addr Address to check
    /// @return A bitmask of permissions for an address
    function permissionMask(address addr) external view returns (uint256);

    /// @notice Return all addresses where rawPermissionMask bit for permissionId is set to 1.
    /// @param permissionId Id of the permission to check
    /// @return A list of dirty addresses
    function dirtyAddresses(uint8 permissionId) external view returns (address[] memory);

    /// @notice Permission addresses staged for commit.
    function stagedPermissionAddresses() external view returns (address[] memory);

    /// @notice Returns a bitmask of permissions for a staged address.
    function stagedPermissionMask(address addr) external view returns (uint256);

    /// @notice Timestamp after which staged addresses can be committed.
    function permissionAddressesTimestamp() external view returns (uint256);

    /// @notice Max different ERC20 token addresses that could be managed by the protocol.
    function maxTokensPerVault() external view returns (uint256);

    /// @notice The delay for committing any governance params.
    function governanceDelay() external view returns (uint256);

    /// @notice The address of the protocol treasury.
    function protocolTreasury() external view returns (address);

    /// @notice Permissions mask which defines if ordinary permission should be reverted. This bitmask is xored with ordinary mask.
    function allowDenyMask() external view returns (uint256);

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
    function revokePermissions(address target, uint8[] memory permissionIds) external;

    /// @notice Commit pending params.
    function commitParams() external;
}
