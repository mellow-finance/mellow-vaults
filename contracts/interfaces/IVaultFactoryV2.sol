// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernance.sol";
import "./IVault.sol";

interface IVaultFactoryV2 {
    /// @notice Deploy a new vault
    /// @param vaultGovernance Reference to Vault Governance
    /// @param options Deployment options (varies between vault factories)
    function deployVault(IVaultGovernance vaultGovernance, bytes calldata options) external returns (IVault vault);
}
