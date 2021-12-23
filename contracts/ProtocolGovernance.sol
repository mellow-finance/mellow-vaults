// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./DefaultAccessControl.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./libraries/DelayedAddressPermissions.sol";

/// @notice Governance that manages all params common for Mellow Permissionless Vaults protocol.
contract ProtocolGovernance is IProtocolGovernance, DefaultAccessControl {
    using DelayedAddressPermissions for DelayedAddressPermissions.BitMap;

    uint256 public constant MAX_GOVERNANCE_DELAY = 7 days;
    uint256 public pendingParamsTimestamp;
    Params public params;
    Params public pendingParams;

    DelayedAddressPermissions.BitMap private _acl;

    /// @notice Creates a new contract.
    /// @param admin Initial admin of the contract
    constructor(address admin) DefaultAccessControl(admin) {}

    // -------------------  PUBLIC, VIEW  -------------------

    function hasClaimPermission(address addr) external view returns (bool) {
        return _acl.hasPermissionId(addr, uint8(Permissions.CLAIM));
    }

    function hasERC20TransferPermission(address addr) external view returns (bool) {
        return _acl.hasPermissionId(addr, uint8(Permissions.ERC20_TRANSFER)) ||
            _acl.hasPermissionId(addr, uint8(Permissions.ERC20_OPERATE)) || 
            _acl.hasPermissionId(addr, uint8(Permissions.ERC20_VAULT_TOKEN));
    }

    function hasERC20OperatePermission(address addr) external view returns (bool) {
        return _acl.hasPermissionId(addr, uint8(Permissions.ERC20_OPERATE)) ||
            _acl.hasPermissionId(addr, uint8(Permissions.ERC20_VAULT_TOKEN));
    }

    function hasERC20VaultTokenPermission(address addr) external view returns (bool) {
        return _acl.hasPermissionId(addr, uint8(Permissions.ERC20_VAULT_TOKEN));
    }

    function hasVaultGovernancePermission(address addr) external view returns (bool) {
        return _acl.hasPermissionId(addr, uint8(Permissions.VAULT_GOVERNANCE));
    }

    /// @inheritdoc IProtocolGovernance
    function permissionless() external view returns (bool) {
        return params.permissionless;
    }

    /// @inheritdoc IProtocolGovernance
    function maxTokensPerVault() external view returns (uint256) {
        return params.maxTokensPerVault;
    }

    /// @inheritdoc IProtocolGovernance
    function governanceDelay() external view returns (uint256) {
        return params.governanceDelay;
    }

    /// @inheritdoc IProtocolGovernance
    function protocolTreasury() external view returns (address) {
        return params.protocolTreasury;
    }

    // ------------------- PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE -----------------

    function commitStagedPermissions() external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        _acl.commitStagedPermissions();
    }

    function revokeClaimPermissionFrom(address addr) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        _acl.revokeInstantPermissionId(addr, uint8(IProtocolGovernance.Permissions.CLAIM));
    }

    function revokeVaultGovernancePermissionFrom(address addr) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        _acl.revokeInstantPermissionId(addr, uint8(Permissions.VAULT_GOVERNANCE));
    }

    function revokeERC20VaultTokenPermissionFrom(address addr) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        _acl.revokeInstantPermissionId(addr, uint8(Permissions.ERC20_VAULT_TOKEN));
    }

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    /// @inheritdoc IProtocolGovernance
    function commitParams() external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        require(block.timestamp >= pendingParamsTimestamp, ExceptionsLibrary.TIMESTAMP);
        require(
            pendingParams.maxTokensPerVault != 0 || pendingParams.governanceDelay != 0,
            ExceptionsLibrary.EMPTY_PARAMS
        ); // sanity check for empty params
        params = pendingParams;
        delete pendingParams;
        delete pendingParamsTimestamp;
    }

    function stagePermissions(address[] calldata addresses, uint8[][] calldata permissionIds) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        _acl.stagePermissionIds(addresses, permissionIds, params.governanceDelay);
    }

    function stageGrantERC20VaultTokenPermissions(address[] memory tokens) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        uint8[][] memory permissionIds = new uint8[][](1);
        permissionIds[0] = new uint8[](3);
        permissionIds[0][0] = uint8(Permissions.ERC20_VAULT_TOKEN);
        permissionIds[0][1] = uint8(Permissions.ERC20_OPERATE);
        permissionIds[0][2] = uint8(Permissions.ERC20_TRANSFER);

        _acl.stagePermissionIds(tokens, permissionIds, params.governanceDelay);
    }

    /// @inheritdoc IProtocolGovernance
    function setPendingParams(IProtocolGovernance.Params memory newParams) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        require(params.governanceDelay <= MAX_GOVERNANCE_DELAY, ExceptionsLibrary.MAX_GOVERNANCE_DELAY);
        pendingParams = newParams;
        pendingParamsTimestamp = block.timestamp + params.governanceDelay;
    }
}
