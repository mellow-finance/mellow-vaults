// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./VaultManager.sol";
import "./ERC20Vault.sol";

contract ERC20VaultFactory {
    function deployVault(IVaultGovernance vaultGovernance, address[] memory vaultTokens) external returns (IVault) {
        ERC20Vault vault = new ERC20Vault(vaultGovernance, vaultTokens);
        return IVault(vault);
    }
}
