// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../VaultGovernance.sol";

contract TestVaultGovernance is VaultGovernance {
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    function strategyTreasury(uint256) external pure override returns (address) {
        return address(0);
    }

    function stageDelayedStrategyParams(uint256 nft, bytes memory params) public {
        _stageDelayedStrategyParams(nft, params);
    }

    function stageDelayedProtocolParams(bytes memory params) public {
        _stageDelayedProtocolParams(params);
    }

    function getStagedDelayedStrategyParams(uint256 nft) public view returns (bytes memory) {
        return _stagedDelayedStrategyParams[nft];
    }

    function getStagedDelayedProtocolParams() public view returns (bytes memory) {
        return _stagedDelayedProtocolParams;
    }

    function getDelayedStrategyParamsTimestamp(uint256 nft) public view returns (uint256) {
        return _delayedStrategyParamsTimestamp[nft];
    }

    function getDelayedProtocolParamsTimestamp() public view returns (uint256) {
        return _delayedProtocolParamsTimestamp;
    }

    function getDelayedStrategyParams(uint256 nft) public view returns (bytes memory) {
        return _delayedStrategyParams[nft];
    }

    function getDelayedProtocolParams() public view returns (bytes memory) {
        return _delayedProtocolParams;
    }

    function commitDelayedStrategyParams(uint256 nft) public {
        _commitDelayedStrategyParams(nft);
    }

    function commitDelayedProtocolParams() public {
        _commitDelayedProtocolParams();
    }

    function setStrategyParams(uint256 nft, bytes memory params) public {
        _setStrategyParams(nft, params);
    }

    function setProtocolParams(bytes memory params) public {
        _setProtocolParams(params);
    }

    function getStrategyParams(uint256 nft) public view returns (bytes memory) {
        return _strategyParams[nft];
    }

    function getProtocolParams() public view returns (bytes memory) {
        return _protocolParams;
    }
}