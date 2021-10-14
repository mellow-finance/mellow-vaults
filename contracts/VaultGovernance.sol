// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./DefaultAccessControl.sol";
import "./libraries/Common.sol";

import "./interfaces/IVaultManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultGovernance.sol";

contract VaultGovernance is IVaultGovernance, DefaultAccessControl {
    IVaultManager private _vaultManager;
    IVaultManager private _pendingVaultManager;
    uint256 private _pendingVaultManagerTimestamp;
    address private _strategyTreasury;
    address private _pendingStrategyTreasury;
    uint256 private _pendingStrategyTreasuryTimestamp;

    constructor(
        IVaultManager manager,
        address treasury,
        address admin
    ) DefaultAccessControl(admin) {
        _vaultManager = manager;
        _strategyTreasury = treasury;
    }

    /// -------------------  PUBLIC, VIEW  -------------------

    function vaultManager() public view returns (IVaultManager) {
        return _vaultManager;
    }

    function pendingVaultManager() external view returns (IVaultManager) {
        return _pendingVaultManager;
    }

    function pendingVaultManagerTimestamp() external view returns (uint256) {
        return _pendingVaultManagerTimestamp;
    }

    function strategyTreasury() public view returns (address) {
        return _strategyTreasury;
    }

    function pendingStrategyTreasury() external view returns (address) {
        return _pendingStrategyTreasury;
    }

    function pendingStrategyTreasuryTimestamp() external view returns (uint256) {
        return _pendingStrategyTreasuryTimestamp;
    }

    /// -------------------  PUBLIC, MUTATING, PROTOCOL ADMIN  -------------------

    function setPendingVaultManager(IVaultManager manager) external {
        require(_isProtocolAdmin(), "PADM");
        require(address(manager) != address(0), "ZMG");
        _pendingVaultManager = manager;
        _pendingVaultManagerTimestamp = _vaultManager.governanceParams().protocolGovernance.governanceDelay();
        emit SetPendingVaultManager(manager);
    }

    function commitVaultManager() external {
        require(_isProtocolAdmin(), "PADM");
        require(_pendingVaultManagerTimestamp > 0, "NULL");
        require(block.timestamp > _pendingVaultManagerTimestamp, "TV");
        _vaultManager = _pendingVaultManager;
        emit CommitVaultManager(_vaultManager);
    }

    /// -------------------  PUBLIC, MUTATING, ADMIN  -------------------

    function setPendingStrategyTreasury(address treasury) external {
        require(isAdmin(), "AG");
        require(address(treasury) != address(0), "ZMG");
        _pendingStrategyTreasury = treasury;
        _pendingStrategyTreasuryTimestamp = _vaultManager.governanceParams().protocolGovernance.governanceDelay();
        emit SetPendingStrategyTreasury(treasury);
    }

    function commitStrategyTreasury() external {
        require(isAdmin(), "AG");
        require(_pendingStrategyTreasuryTimestamp > 0, "NULL");
        require(block.timestamp > _pendingStrategyTreasuryTimestamp, "TV");
        _strategyTreasury = _pendingStrategyTreasury;
        emit CommitStrategyTreasury(_strategyTreasury);
    }

    /// -------------------  PRIVATE, VIEW  -------------------

    function _isProtocolAdmin() internal view returns (bool) {
        return _vaultManager.governanceParams().protocolGovernance.isAdmin();
    }
}
