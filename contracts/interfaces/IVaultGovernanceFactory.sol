// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernanceOld.sol";
import "./IVaultManager.sol";

interface IVaultGovernanceFactory {
    /// @notice Deploy new vault governance
    /// @param tokens A set of tokens that will be managed by the Vault
    /// @param manager Reference to Vault Manager
    /// @param treasury Strategy treasury address that will be used to collect Strategy Performance Fee
    /// @param admin Admin of the Vault
    function deployVaultGovernance(
        address[] memory tokens,
        IVaultManager manager,
        address treasury,
        address admin
    ) external returns (IVaultGovernanceOld vaultGovernance);
}
