// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./GovernanceAccessControl.sol";
import "./libraries/Common.sol";

import "./interfaces/IVaultManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultGovernance.sol";

contract VaultGovernance is IVaultGovernance, GovernanceAccessControl {
    IVaultManager private _vaultManager;
    IVaultManager private _pendingVaultManager;
    uint256 private _pendingVaultManagerTimestamp;

    constructor(IVaultManager manager) {
        _vaultManager = manager;
    }

    function vaultManager() public view returns (IVaultManager) {
        return _vaultManager;
    }

    function pendingVaultManager() external view returns (IVaultManager) {
        return _pendingVaultManager;
    }

    function pendingVaultManagerTimestamp() external view returns (uint256) {
        return _pendingVaultManagerTimestamp;
    }

    function setPendingVaultManager(IVaultManager manager) external {
        require(_isGovernanceOrDelegate(), "GD");
        require(address(manager) != address(0), "ZMG");
        _pendingVaultManager = manager;
        _pendingVaultManagerTimestamp = _vaultManager.protocolGovernance().governanceDelay();
        emit SetPendingVaultManager(manager);
    }

    function commitVaultManager() external {
        require(_isGovernanceOrDelegate(), "GD");
        require(_pendingVaultManagerTimestamp > 0, "NULL");
        require(block.timestamp > _pendingVaultManagerTimestamp, "TV");
        _vaultManager = _pendingVaultManager;
        emit CommitVaultManager(_vaultManager);
    }
}
