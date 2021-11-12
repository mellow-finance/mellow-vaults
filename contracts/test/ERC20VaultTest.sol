// SPDX-Licence-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/IVaultGovernance.sol";
import "../interfaces/IVaultFactory.sol";
import "../ERC20Vault.sol";

contract ERC20VaultTest is ERC20Vault {
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        ERC20Vault(vaultGovernance_, vaultTokens_)
    {}

    function setVaultGovernance(address newVaultGovernance) public {
        _vaultGovernance = IVaultGovernance(newVaultGovernance);
    }

    function __collectEarnings(address a, bytes memory b) public view returns (uint256[] memory) {
        return _collectEarnings(a, b);
    }

    function __postReclaimTokens(address a, address[] memory tokens) public view {
        _postReclaimTokens(a, tokens);
    }
}
