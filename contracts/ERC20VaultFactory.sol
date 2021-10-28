// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./ERC20Vault.sol";

contract ERC20VaultFactory {
    function deployVault(IVaultGovernance vaultGovernance, bytes calldata options) 
        external returns (IVault) {
        address[] memory vaultTokens = abi.decode(options, (address[]));
        ERC20Vault vault = new ERC20Vault(vaultGovernance, vaultTokens);
        return IVault(vault);
    }
}
