// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./DefaultAccessControl.sol";

contract ProtocolGovernance is IProtocolGovernance, DefaultAccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _claimAllowlist;
    address[] private _pendingClaimAllowlistAdd;
    uint256 public pendingClaimAllowlistAddTimestamp;

    IProtocolGovernance.Params public params;
    Params public pendingParams;

    uint256 public pendingParamsTimestamp;

    constructor(address admin) DefaultAccessControl(admin) {}

    /// -------------------  PUBLIC, VIEW  -------------------
    function claimAllowlist() external view returns (address[] memory) {
        uint256 l = _claimAllowlist.length();
        address[] memory res = new address[](l);
        for (uint256 i = 0; i < l; i++) {
            res[i] = _claimAllowlist.at(i);
        }
        return res;
    }

    function pendingClaimAllowlistAdd() external view returns (address[] memory) {
        return _pendingClaimAllowlistAdd;
    }

    function isAllowedToClaim(address addr) external view returns (bool) {
        return _claimAllowlist.contains(addr);
    }

    function maxTokensPerVault() external view returns (uint256) {
        return params.maxTokensPerVault;
    }

    function governanceDelay() external view returns (uint256) {
        return params.governanceDelay;
    }

    function strategyPerformanceFee() external view returns (uint256) {
        return params.strategyPerformanceFee;
    }

    function protocolPerformanceFee() external view returns (uint256) {
        return params.protocolPerformanceFee;
    }

    function protocolExitFee() external view returns (uint256) {
        return params.protocolExitFee;
    }

    function protocolTreasury() external view returns (address) {
        return params.protocolTreasury;
    }

    function gatewayVaultManager() external view override returns (IGatewayVaultManager) {
        return params.gatewayVaultManager;
    }

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE, DELAY  -------------------

    function setPendingClaimAllowlistAdd(address[] calldata addresses) external {
        require(isAdmin(), "ADM");
        _pendingClaimAllowlistAdd = addresses;
        pendingClaimAllowlistAddTimestamp = block.timestamp + params.governanceDelay;
    }

    function removeFromClaimAllowlist(address addr) external {
        require(isAdmin(), "ADM");
        if (!_claimAllowlist.contains(addr)) {
            return;
        }
        _claimAllowlist.remove(addr);
    }

    function setPendingParams(IProtocolGovernance.Params memory newParams) external {
        require(isAdmin(), "ADM");
        pendingParams = newParams;
        pendingParamsTimestamp = block.timestamp + params.governanceDelay;
    }

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE, IMMEDIATE  -------------------

    function commitClaimAllowlistAdd() external {
        require(isAdmin(), "ADM");
        require((block.timestamp > pendingClaimAllowlistAddTimestamp) && (pendingClaimAllowlistAddTimestamp > 0), "TS");
        for (uint256 i = 0; i < _pendingClaimAllowlistAdd.length; i++) {
            _claimAllowlist.add(_pendingClaimAllowlistAdd[i]);
        }
        delete _pendingClaimAllowlistAdd;
        delete pendingClaimAllowlistAddTimestamp;
    }

    function commitParams() external {
        require(isAdmin(), "ADM");
        require(block.timestamp > pendingParamsTimestamp, "TS");
        require(pendingParams.maxTokensPerVault > 0 || pendingParams.governanceDelay > 0, "P0"); // sanity check for empty params
        params = pendingParams;
        delete pendingParams;
        delete pendingParamsTimestamp;
    }
}
