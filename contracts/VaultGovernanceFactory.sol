// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./libraries/Common.sol";

import "./interfaces/IVaultGovernanceFactory.sol";
import "./interfaces/IVaultGovernanceOld.sol";
import "./VaultGovernanceOld.sol";

contract VaultGovernanceFactory {
    /// @notice Deploy a govrenance new contract
    /// @param tokens A set of tokens that will be managed by the Vault
    /// @param manager Reference to Gateway Vault Manager
    /// @param treasury Strategy treasury address that will be used to collect Strategy Performance Fee
    /// @param admin Admin of the Vault
    function deployVaultGovernance(
        address[] memory tokens,
        IVaultManager manager,
        address treasury,
        address admin
    ) external returns (IVaultGovernanceOld) {
        require(treasury != address(0), "TZA");
        require(admin != address(0), "AZA");
        VaultGovernanceOld vaultGovernance = new VaultGovernanceOld(tokens, manager, treasury, admin);
        return IVaultGovernanceOld(vaultGovernance);
    }
}
