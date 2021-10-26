// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultGovernance.sol";
import "./interfaces/IProtocolGovernance.sol";

contract VaultGovernance is IVaultGovernance {
    IProtocolGovernance private _protocolGovernance;
    mapping(uint256 => bytes) private _delayedStrategyParams;
    mapping(uint256 => bytes) private _delayedProtocolParams;
    mapping(uint256 => bytes) private _strategyParams;
    mapping(uint256 => bytes) private _protocolParams;
    bytes private _protocolCommonParams;

    constructor(IProtocolGovernance protocolGovernance_) {
        _protocolGovernance = protocolGovernance_;
    }

    function protocolGovernance() external returns (IProtocolGovernance) {
        return _protocolGovernance;
    }
}
