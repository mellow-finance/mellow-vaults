// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IDefaultAccessControl.sol";

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

    enum Permissions {
        ERC20_TRANSFER,
        ERC20_OPERATE,
        ERC20_VAULT_TOKEN,
        CLAIM,
        VAULT_GOVERNANCE
    }

    // -------------------  PUBLIC, VIEW  -------------------

    /// @notice Checks if address is allowed to claim
    function hasClaimPermission(address addr) external view returns (bool);

    /// @notice Checks if given ERC20 token is allowed to be transferred
    function hasERC20TransferPermission(address addr) external view returns (bool);

    /// @notice Checks if given ERC20 token is allowed to be operated (swaped, transferred, etc)
    function hasERC20OperatePermission(address addr) external view returns (bool);

    /// @notice Checks if given ERC20 token is allowed to be a vault token
    function hasERC20VaultTokenPermission(address addr) external view returns (bool);

    /// @notice Checks if given address is allowed to deploy and manage vaults
    function hasVaultGovernancePermission(address addr) external view returns (bool);

    /// @notice If `false` only admins can deploy new vaults, o/w anyone can deploy a new vault.
    function permissionless() external view returns (bool);

    /// @notice Max different ERC20 token addresses that could be managed by the protocol.
    function maxTokensPerVault() external view returns (uint256);

    /// @notice The delay for committing any governance params.
    function governanceDelay() external view returns (uint256);

    /// @notice The address of the protocol treasury.
    function protocolTreasury() external view returns (address);

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    /// @notice Set new pending params.
    /// @param newParams newParams to set
    function setPendingParams(Params memory newParams) external;

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------

    /// @notice Commit pending params.
    function commitParams() external;
}
