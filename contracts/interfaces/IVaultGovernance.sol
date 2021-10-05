// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultManager.sol";

interface IVaultGovernance {
    function vaultManager() external view returns (IVaultManager);

    function pendingVaultManager() external view returns (IVaultManager);

    function pendingVaultManagerTimestamp() external view returns (uint256);

    function setPendingVaultManager(IVaultManager newManager) external;

    function commitVaultManager() external;

    event SetPendingVaultManager(IVaultManager);
    event CommitVaultManager(IVaultManager);
}
