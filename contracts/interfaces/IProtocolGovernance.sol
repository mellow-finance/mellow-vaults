// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IDefaultAccessControl.sol";
import "./IGatewayVaultManager.sol";

interface IProtocolGovernance is IDefaultAccessControl {
    /// @notice Common protocol params
    /// @param maxTokensPerVault Max different token addresses that could be managed by the protocol
    /// @param governanceDelay The delay (in secs) that must pass before setting new pending params to commiting them
    /// @param strategyPerformanceFee Strategy performance fee percent of the strategy (measured in 10 ** 9, i.e. you have to divide this param to this number to get the actual percentage)
    /// @param protocolPerformanceFee Protocol performance fee percent of the strategy (measured same as strategyPerformanceFee)
    /// @param protocolExitFee Protocol exit fee percent of the strategy (measured same as strategyPerformanceFee)
    /// @param protocolTreasury The address that collect protocol fees
    /// @param gatewayVaultManager Gateway VaultManager of the protocol
    struct Params {
        uint256 maxTokensPerVault;
        uint256 governanceDelay;
        uint256 strategyPerformanceFee;
        uint256 protocolPerformanceFee;
        uint256 protocolExitFee;
        address protocolTreasury;
        IGatewayVaultManager gatewayVaultManager;
    }

    // -------------------  PUBLIC, VIEW  -------------------

    /// @notice Addresses allowed to claim liquidity mining rewards from
    function claimAllowlist() external view returns (address[] memory);

    /// @notice Pending addresses to be added to claimAllowlist
    function pendingClaimAllowlistAdd() external view returns (address[] memory);

    /// @notice Check if address is allowed to claim
    function isAllowedToClaim(address addr) external view returns (bool);

    /// @notice Max different token addresses that could be managed by the protocol
    function maxTokensPerVault() external view returns (uint256);

    /// @notice The delay for committing any governance params
    function governanceDelay() external view returns (uint256);

    /// @notice Strategy performance fee percent of the strategy (measured in 10 ** 9, i.e. you have to divide this param to this number to get the actual percentage)
    function strategyPerformanceFee() external view returns (uint256);

    /// @notice Protocol performance fee percent of the strategy (measured same as strategyPerformanceFee)
    function protocolPerformanceFee() external view returns (uint256);

    /// @notice Protocol exit fee percent of the strategy (measured same as strategyPerformanceFee)
    function protocolExitFee() external view returns (uint256);

    /// @notice The address that collect protocol fees
    function protocolTreasury() external view returns (address);

    /// @notice Gateway VaultManager of the protocol
    function gatewayVaultManager() external view returns (IGatewayVaultManager);

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    /// @notice Set new pending params
    /// @param newParams newParams to set
    function setPendingParams(Params memory newParams) external;

    // -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------

    /// @notice Commit pending params
    function commitParams() external;
}
