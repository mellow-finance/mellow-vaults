// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/IVaultGovernance.sol";
import "../AaveVault.sol";

contract AaveVaultTest is AaveVault {
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_) AaveVault(vaultGovernance_, vaultTokens_) {}

    function isValidEdge(address from, address to) public view returns (bool) {
        return _isValidEdge(from, to);
    }

    function setVaultGovernance(address newVaultGovernance) public {
        _vaultGovernance = IVaultGovernance(newVaultGovernance);
    }
}
