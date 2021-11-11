// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/IVaultGovernance.sol";
import "../interfaces/IVaultFactory.sol";
import "../UniV3Vault.sol";

contract UniV3VaultTest is UniV3Vault {
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_, uint24 fee) UniV3Vault(vaultGovernance_, vaultTokens_, fee) {}

    function isValidEdge(address from, address to) public view returns (bool) {
        return _isValidEdge(from, to);
    }

    function setVaultGovernance(address newVaultGovernance) public {
        _vaultGovernance = IVaultGovernance(newVaultGovernance);
    }
}
