// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./access/GovernanceAccessControl.sol";

contract ProtocolGovernance is IProtocolGovernance, GovernanceAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _pullAllowlist;
    Params public params;
    struct Params {
        uint256 maxTokensPerVault;
        uint256 governanceDelay;
        uint256 protocolFee;
        address protocolTreasury;
    }
    address[] private _pendingPullAllowlistAdd;
    Params public pendingParams;

    uint256 public pendingPullAllowlistAddTimestamp;
    uint256 public pendingParamsTimestamp;

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

    function removeFromPullAllowlist(address addr) external {
        require(_isGovernanceOrDelegate(), "GD");
        if (!_pullAllowlist.contains(addr)) {
            return;
        }
        _pullAllowlist.remove(addr);
    }

    function setPendingParams(Params memory newParams) external {
        require(_isGovernanceOrDelegate(), "GD");
        pendingParams = newParams;
        pendingParamsTimstamp = block.timestamp + governanceDelay;
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

    function commitParams() external {
        require(_isGovernanceOrDelegate(), "GD");
        require(block.timestamp > pendingParamsTimestamp, "TS");
        require(pendingParams.maxTokensPerVault > 0 || governanceDelay > 0, "P0"); // sanity check
        params = pendingParams;
        delete pendingParams;
        delete pendingParamsTimestamp;
    }
}
