// SPDX-Licence-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/IVaultGovernance.sol";
import "../interfaces/IVaultFactory.sol";
import "../ERC20Vault.sol";

contract ERC20VaultTest is ERC20Vault {

    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_) ERC20Vault(vaultGovernance_, vaultTokens_) {}

    function isValidEdge(address from, address to) public view returns (bool) {
        return _isValidEdge(from, to);
    }

    function setVaultGovernance(address newVaultGovernance) public {
        _vaultGovernance = IVaultGovernance(newVaultGovernance);
    }
}
