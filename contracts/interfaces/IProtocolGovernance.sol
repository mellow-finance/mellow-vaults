// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IProtocolGovernance {
    /// -------------------  PUBLIC, VIEW  -------------------

    function pullAllowlist() external view returns (address[] memory);

    function pendingPullAllowlistAdd() external view returns (address[] memory);

    function isAllowedToPull(address addr) external view returns (bool);

    function maxTokensPerVault() external view returns (uint256);

    function governanceDelay() external view returns (uint256);

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    function setPendingPullAllowlistAdd(address[] calldata addresses) external;

    function setPendingMaxTokensPerVault(uint256 maxTokens) external;

    function setPendingGovernanceDelay(uint256 newDelay) external;

    function removeFromPullAllowlist(address addr) external;

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------

    function commitPullAllowlistAdd() external;

    function commitMaxTokensPerVault() external;

    function commitGovernanceDelay() external;
}
