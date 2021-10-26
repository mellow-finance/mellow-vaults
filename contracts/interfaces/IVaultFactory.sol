// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernanceOld.sol";
import "./IVault.sol";

interface IVaultFactory {
    /// @notice Deploy a new vault
    /// @param vaultGovernance Reference to Vault Governance
    /// @param options Deployment options (varies between vault factories)
    function deployVault(IVaultGovernanceOld vaultGovernance, bytes calldata options) external returns (IVault vault);
}
