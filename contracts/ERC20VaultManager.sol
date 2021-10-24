// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IVaultGovernanceFactory.sol";
import "./VaultManager.sol";

contract ERC20VaultManager is VaultManager {
    /// @notice Creates a new contract
    /// @param name Name of the ERC-721 token
    /// @param symbol Symbol of the ERC-721 token
    /// @param factory Vault Factory reference
    /// @param governanceFactory VaultGovernance Factory reference
    /// @param permissionless Anyone can create a new vault
    /// @param governance Refernce to the Governance of the protocol
    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        IVaultGovernanceFactory governanceFactory,
        bool permissionless,
        IProtocolGovernance governance
    ) VaultManager(name, symbol, factory, governanceFactory, permissionless, governance) {}
}
