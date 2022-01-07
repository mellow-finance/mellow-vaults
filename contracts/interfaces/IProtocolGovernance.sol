// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./utils/IDefaultAccessControl.sol";

interface IProtocolGovernance is IDefaultAccessControl {
    /// @notice CommonLibrary protocol params.
    /// @param permissionless If `true` anyone can spawn vaults, o/w only Protocol Governance Admin
    /// @param maxTokensPerVault Max different token addresses that could be managed by the protocol
    /// @param governanceDelay The delay (in secs) that must pass before setting new pending params to commiting them
    /// @param forceAllowMask If a permission bit is set in this mask it forces all addresses to have this permission as true
    struct Params {
        uint256 maxTokensPerVault;
        uint256 governanceDelay;
        address protocolTreasury;
        uint256 forceAllowMask;
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

    /// @notice Returns address by index.
    /// The address is expected to have at least one granted permission, otherwise it will be deleted.
    function permissionAddressAt(uint256 index) external view returns (address);

    /// @notice Returns timestamp after which staged granted permissions for the given address can be committed.
    /// Returns zero if there are no staged permission grants.
    /// @param target The given address.
    function grantedPermissionAddressTimestamps(address target) external view returns (uint256);

    /// @notice Returns timestamp after which staged pending protocol parameters can be committed.
    /// Returns zero if there are no staged parameters.
    function pendingParamsTimestamp() external view returns (uint256);

    /// @notice Raw bitmask of permissions for an address (forceAllowMask is not applied).
    /// @param addr Address to check.
    /// @return A bitmask of permissions for an address
    function rawPermissionMask(address addr) external view returns (uint256);

    /// @notice Bitmask of true permissions for an address (forceAllowMask is applied).
    /// @param addr Address to check.
    /// @return A bitmask of permissions for an address
    function permissionMask(address addr) external view returns (uint256);

    /// @notice Return all addresses where rawPermissionMask bit for permissionId is set to 1.
    /// @param permissionId Id of the permission to check.
    /// @return A list of dirty addresses.
    function addressesByPermissionIdRaw(uint8 permissionId) external view returns (address[] memory);

    /// @notice Permission addresses staged for commit.
    function stagedPermissionAddresses() external view returns (address[] memory);

    /// @notice Returns staged granted permission bitmask for the given address.
    /// @param target The given address.
    function stagedGrantedPermissionMasks(address target) external view returns (uint256);

    /// @notice Max different ERC20 token addresses that could be managed by the protocol.
    function maxTokensPerVault() external view returns (uint256);

    /// @notice The delay for committing any governance params.
    function governanceDelay() external view returns (uint256);

    /// @notice The address of the protocol treasury.
    function protocolTreasury() external view returns (address);

    /// @notice Permissions mask which defines if ordinary permission should be reverted. This bitmask is xored with ordinary mask.
    function forceAllowMask() external view returns (uint256);

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
    function rollbackStagedGrantedPermissions() external;

    /// @notice Commits all staged granted permissions optimistically.
    /// Addresse skipped if governance delay is not passed, transation doesn't revert.
    function commitStagedPermissions() external;

    /// @notice Comits staged granted permissions for the given address.
    /// Reverts if governance delay is not passed.
    /// @param target The given address
    function commitStagedPermission(address target) external;

    /// @notice Revoke permission instant.
    /// @param target Target address
    /// @param permissionIds A list of permission ids to revoke
    function revokePermissions(address target, uint8[] memory permissionIds) external;

    /// @notice Commit pending params.
    function commitParams() external;
}
