// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IDefaultAccessControl.sol";

interface IProtocolGovernance is IDefaultAccessControl {
    /// -------------------  PUBLIC, VIEW  -------------------

    struct Params {
        uint256 maxTokensPerVault;
        uint256 governanceDelay;
        uint256 strategyPerformanceFee;
        uint256 protocolPerformanceFee;
        uint256 protocolExitFee;
        address protocolTreasury;
    }

    function pullAllowlist() external view returns (address[] memory);

    function pendingPullAllowlistAdd() external view returns (address[] memory);

    function isAllowedToPull(address addr) external view returns (bool);

    function claimAllowlist() external view returns (address[] memory);

    function pendingClaimAllowlistAdd() external view returns (address[] memory);

    function isAllowedToClaim(address addr) external view returns (bool);

    function maxTokensPerVault() external view returns (uint256);

    function governanceDelay() external view returns (uint256);

    function strategyPerformanceFee() external view returns (uint256);

    function protocolPerformanceFee() external view returns (uint256);

    function protocolExitFee() external view returns (uint256);

    function protocolTreasury() external view returns (address);

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    function setPendingPullAllowlistAdd(address[] calldata addresses) external;

    function setPendingParams(Params memory newParams) external;

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------

    function commitPullAllowlistAdd() external;

    function commitParams() external;

    function removeFromPullAllowlist(address addr) external;
}
