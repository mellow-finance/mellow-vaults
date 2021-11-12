// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/IVaultGovernance.sol";
import "../AaveVault.sol";

contract AaveVaultTest is AaveVault {
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        AaveVault(vaultGovernance_, vaultTokens_)
    {}

    function setATokens(address[] memory aTokens) public {
        _aTokens = aTokens;
    }

    function setBaseBalances(uint256[] memory baseBalances) public {
        _baseBalances = baseBalances;
    }

    function setVaultGovernance(address newVaultGovernance) public {
        _vaultGovernance = IVaultGovernance(newVaultGovernance);
    }
}
