// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultManager.sol";

interface IVaultGovernance {
    function isProtocolAdmin() external view returns (bool);

    function vaultTokens() external view returns (address[] memory);

    function isVaultToken(address token) external view returns (bool);

    function vaultManager() external view returns (IVaultManager);

    function pendingVaultManager() external view returns (IVaultManager);

    function pendingVaultManagerTimestamp() external view returns (uint256);

    function setPendingVaultManager(IVaultManager newManager) external;

    function commitVaultManager() external;

    function strategyTreasury() external view returns (address);

    function pendingStrategyTreasury() external view returns (address);

    function pendingStrategyTreasuryTimestamp() external view returns (uint256);

    function setPendingStrategyTreasury(address newTreasury) external;

    function commitStrategyTreasury() external;

    event SetPendingVaultManager(IVaultManager);
    event CommitVaultManager(IVaultManager);
    event SetPendingStrategyTreasury(address);
    event CommitStrategyTreasury(address);
}
