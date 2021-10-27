// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./VaultManager.sol";
import "./AaveVault.sol";

contract AaveVaultFactory {
    function deployVault(IVaultGovernance vaultGovernance, address[] memory vaultTokens) external returns (IVault) {
        AaveVault vault = new AaveVault(vaultGovernance, vaultTokens);
        return IVault(vault);
    }
}
