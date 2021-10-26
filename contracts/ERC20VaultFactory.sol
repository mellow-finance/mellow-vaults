// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./interfaces/IVaultFactory.sol";
import "./VaultManager.sol";
import "./ERC20Vault.sol";

contract ERC20VaultFactory is IVaultFactory {
    /// @inheritdoc IVaultFactory
    function deployVault(IVaultGovernanceOld vaultGovernance, bytes calldata) external override returns (IVault) {
        ERC20Vault vault = new ERC20Vault(vaultGovernance);
        return IVault(vault);
    }
}
