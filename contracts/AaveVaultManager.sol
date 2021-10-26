// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IAaveVaultManager.sol";
import "./interfaces/external/aave/ILendingPool.sol";
import "./VaultManager.sol";

contract AaveVaultManager is IAaveVaultManager, VaultManager {
    ILendingPool _lendingPool;

    /// @notice Creates a new contract
    /// @param name Name of the ERC-721 token
    /// @param symbol Symbol of the ERC-721 token
    /// @param factory Vault Factory reference
    /// @param governanceFactory VaultGovernanceOld Factory reference
    /// @param permissionless Anyone can create a new vault
    /// @param governance Refernce to the Governance of the protocol
    /// @param pool Reference to Aave Lending Pool
    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        IVaultGovernanceFactory governanceFactory,
        bool permissionless,
        IProtocolGovernance governance,
        ILendingPool pool
    ) VaultManager(name, symbol, factory, governanceFactory, permissionless, governance) {
        _lendingPool = pool;
    }

    /// @notice Reference to Aave Lending Pool
    function lendingPool() external view returns (ILendingPool) {
        return _lendingPool;
    }
}
