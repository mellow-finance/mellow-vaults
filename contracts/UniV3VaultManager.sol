// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IUniV3VaultManager.sol";
import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./VaultManager.sol";

contract UniV3VaultManager is IUniV3VaultManager, VaultManager {
    INonfungiblePositionManager private _positionManager;

    /// @notice Creates a new contract
    /// @param name Name of the ERC-721 token
    /// @param symbol Symbol of the ERC-721 token
    /// @param factory Vault Factory reference
    /// @param governanceFactory VaultGovernance Factory reference
    /// @param permissionless Anyone can create a new vault
    /// @param governance Refernce to the Governance of the protocol
    /// @param uniV3PositionManager Reference to Uniswap V3 Nonfungible Position Manager
    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        IVaultGovernanceFactory governanceFactory,
        bool permissionless,
        IProtocolGovernance governance,
        INonfungiblePositionManager uniV3PositionManager
    ) VaultManager(name, symbol, factory, governanceFactory, permissionless, governance) {
        _positionManager = uniV3PositionManager;
    }

    function positionManager() external view returns (INonfungiblePositionManager) {
        return _positionManager;
    }
}
