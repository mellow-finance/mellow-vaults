// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../interfaces/IAaveVaultGovernance.sol";
import "../AaveVaultGovernance.sol";
import "../VaultGovernance.sol";
import "hardhat/console.sol";

contract AaveVaultGovernanceTest is AaveVaultGovernance {
    constructor(InternalParams memory internalParams_, DelayedProtocolParams memory delayedProtocolParams_)
        AaveVaultGovernance(internalParams_, delayedProtocolParams_)
    {
        delete _delayedProtocolParams;
        console.log(_delayedProtocolParams.length);
    }
}
