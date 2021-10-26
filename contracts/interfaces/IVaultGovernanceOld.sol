// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultManager.sol";

interface IVaultGovernanceOld {
    // -------------------  PUBLIC, MUTATING, VIEW  -------------------

    /// @notice Checks that sender is protocol admin
    function isProtocolAdmin(address sender) external view returns (bool);

    /// @notice Tokens managed by the vault
    function vaultTokens() external view returns (address[] memory);

    /// @notice Checks if token is managed by the Vault
    function isVaultToken(address token) external view returns (bool);

    /// @notice Reference to Vault Manager
    function vaultManager() external view returns (IVaultManager);

    /// @notice Pending new vault manager that will be committed
    function pendingVaultManager() external view returns (IVaultManager);

    /// @notice When Pending Vault Manager could be committed
    function pendingVaultManagerTimestamp() external view returns (uint256);

    /// @notice Set new pending vault manager that will be committed
    function setPendingVaultManager(IVaultManager newManager) external;

    /// @notice Commit new vault manager
    function commitVaultManager() external;

    /// @notice Strategy treasury that will receive strategy performance fees
    function strategyTreasury() external view returns (address);

    /// @notice Pending strategy treasury that will be committed
    function pendingStrategyTreasury() external view returns (address);

    /// @notice When Pending strategy treasury can be committed (timestamp in secs)
    function pendingStrategyTreasuryTimestamp() external view returns (uint256);

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    /// @notice Stage new pending strategy treasury
    function setPendingStrategyTreasury(address newTreasury) external;

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------
    /// @notice Commit pending strategy treasury
    function commitStrategyTreasury() external;

    event SetPendingVaultManager(IVaultManager);
    event CommitVaultManager(IVaultManager);
    event SetPendingStrategyTreasury(address);
    event CommitStrategyTreasury(address);
}
