// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "./DefaultAccessControl.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./libraries/AddressPermissions.sol";
import "./AddressPermissionControl.sol";

/// @notice Governance that manages all params common for Mellow Permissionless Vaults protocol.
contract ProtocolGovernance is IProtocolGovernance, DefaultAccessControl, AddressPermissionControl {
    uint256 public constant MAX_GOVERNANCE_DELAY = 7 days;
    uint256 public pendingParamsTimestamp;
    Params public params;
    Params public pendingParams;

    /// @notice Creates a new contract.
    /// @param admin Initial admin of the contract
    constructor(address admin) DefaultAccessControl(admin) {}

    // -------------------  PUBLIC, VIEW  -------------------

    function hasPermissionId(address addr, uint8 permissionId) external view returns (bool) {
        return _hasPermissionId(addr, permissionId);
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
        _commitStagedPermissions();
    }

    function revokeInstantPermissionId(address addr, uint8 permissionId) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        _revokeInstantPermissionId(addr, permissionId);
    }

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

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    function stagePermissionIds(address[] calldata addresses_, uint8[][] calldata permissionIds) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        _stagePermissionIds(addresses_, permissionIds, params.governanceDelay);
    }

    function stageGrantERC20VaultTokenPermissions(address[] memory tokens) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        uint8[][] memory permissionIds = new uint8[][](1);
        permissionIds[0] = new uint8[](3);
        permissionIds[0][0] = AddressPermissions.ERC20_VAULT_TOKEN;
        permissionIds[0][1] = AddressPermissions.ERC20_SWAP;
        permissionIds[0][2] = AddressPermissions.ERC20_TRANSFER;

        _stagePermissionIds(tokens, permissionIds, params.governanceDelay);
    }

    /// @inheritdoc IProtocolGovernance
    function setPendingParams(IProtocolGovernance.Params memory newParams) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        require(params.governanceDelay <= MAX_GOVERNANCE_DELAY, ExceptionsLibrary.MAX_GOVERNANCE_DELAY);
        pendingParams = newParams;
        pendingParamsTimestamp = block.timestamp + params.governanceDelay;
    }
}
