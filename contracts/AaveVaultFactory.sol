// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./VaultManager.sol";
import "./AaveVault.sol";

contract AaveVaultFactory is IVaultFactory {
    function deployVault(IVaultGovernance vaultGovernance, bytes calldata) external override returns (IVault) {
        AaveVault vault = new AaveVault(vaultGovernance);
        return IVault(vault);
    }
}
