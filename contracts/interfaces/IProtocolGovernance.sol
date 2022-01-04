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

    /// @notice Checks if address has permission staged
    /// @param addr Address to check
    /// @param permissionId Permission id to check
    function hasStagedPermission(address addr, uint8 permissionId) external view returns (bool);

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
