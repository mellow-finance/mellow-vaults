// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IGovernance.sol";
import "./access/GovernanceAccessControl.sol";

contract Governance is IGovernance, GovernanceAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _pullAllowlist;
    uint256 public maxTokensPerVault = 10;
    uint256 public governanceDelay = 86400;

    address[] private _pendingPullAllowlistAdd;
    uint256 public pendingGovernanceDelay;
    uint256 public pendingMaxTokensPerVault;

    uint256 public pendingPullAllowlistAddTimestamp;
    uint256 public pendingMaxTokensPerVaultTimestamp;
    uint256 public pendingGovernanceDelayTimestamp;

    /// -------------------  PUBLIC, VIEW  -------------------
    function pullAllowlist() external view returns (address[] memory) {
        uint256 l = _pullAllowlist.length();
        address[] memory res = new address[](l);
        for (uint256 i = 0; i < l; i++) {
            res[i] = _pullAllowlist.at(i);
        }
        return res;
    }

    function pendingPullAllowlistAdd() external view returns (address[] memory) {
        return _pendingPullAllowlistAdd;
    }

    function isAllowedToPull(address addr) external view returns (bool) {
        return _pullAllowlist.contains(addr);
    }

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    function setPendingPullAllowlistAdd(address[] calldata addresses) external {
        require(_isGovernanceOrDelegate(), "GD");
        _pendingPullAllowlistAdd = addresses;
        pendingPullAllowlistAddTimestamp = block.timestamp + governanceDelay;
    }

    function setPendingMaxTokensPerVault(uint256 maxTokens) external {
        require(_isGovernanceOrDelegate(), "GD");
        pendingMaxTokensPerVault = maxTokens;
        pendingMaxTokensPerVaultTimestamp = block.timestamp + governanceDelay;
    }

    function setPendingGovernanceDelay(uint256 newDelay) external {
        require(_isGovernanceOrDelegate(), "GD");
        pendingGovernanceDelay = newDelay;
        pendingGovernanceDelayTimestamp = block.timestamp + governanceDelay;
    }

    function removeFromPullAllowlist(address addr) external {
        require(_isGovernanceOrDelegate(), "GD");
        if (!_pullAllowlist.contains(addr)) {
            return;
        }
        _pullAllowlist.remove(addr);
    }

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------

    function commitPullAllowlistAdd() external {
        require(_isGovernanceOrDelegate(), "GD");
        require((block.timestamp > pendingPullAllowlistAddTimestamp) && (pendingPullAllowlistAddTimestamp > 0), "TS");
        for (uint256 i = 0; i < _pendingPullAllowlistAdd.length; i++) {
            _pullAllowlist.add(_pendingPullAllowlistAdd[i]);
        }
        delete _pendingPullAllowlistAdd;
        delete pendingPullAllowlistAddTimestamp;
    }

    function commitMaxTokensPerVault() external {
        require(_isGovernanceOrDelegate(), "GD");
        require((block.timestamp > pendingMaxTokensPerVaultTimestamp) && (pendingMaxTokensPerVaultTimestamp > 0), "TS");
        maxTokensPerVault = pendingMaxTokensPerVault;
        delete pendingMaxTokensPerVault;
        delete pendingMaxTokensPerVaultTimestamp;
    }

    function commitGovernanceDelay() external {
        require(_isGovernanceOrDelegate(), "GD");
        require((block.timestamp > pendingGovernanceDelayTimestamp) && (pendingGovernanceDelayTimestamp > 0), "TS");
        maxTokensPerVault = pendingGovernanceDelay;
        delete pendingGovernanceDelay;
        delete pendingGovernanceDelayTimestamp;
    }
}
