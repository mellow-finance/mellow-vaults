// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../VaultGovernance.sol";

contract TestVaultGovernance is VaultGovernance {
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    function strategyTreasury(uint256 nft) external pure override returns (address) {
        return address(0);
    }
}