// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./ERC20Vault.sol";

/// @notice Helper contract for ERC20VaultGovernance that can create new ERC20 Vaults
contract ERC20VaultFactory is IVaultFactory {
    IVaultGovernance public vaultGovernance;

    /// @notice Creates a new contract
    /// @param vaultGovernance_ Reference to VaultGovernance of this VaultKind
    constructor(IVaultGovernance vaultGovernance_) {
        vaultGovernance = vaultGovernance_;
    }

    /// @inheritdoc IVaultFactory
    function deployVault(address[] memory vaultTokens, bytes memory) external returns (IVault) {
        require(msg.sender == address(vaultGovernance), "VG");
        ERC20Vault vault = new ERC20Vault(vaultGovernance, vaultTokens);
        return IVault(vault);
    }
}
