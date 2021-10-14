// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IUniV3VaultManager.sol";
import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./VaultManager.sol";

contract UniV3VaultManager is IUniV3VaultManager, VaultManager {
    INonfungiblePositionManager private _positionManager;

    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        IVaultGovernanceFactory goveranceFactory,
        bool permissionless,
        IProtocolGovernance governance,
        INonfungiblePositionManager uniV3PositionManager
    ) VaultManager(name, symbol, factory, goveranceFactory, permissionless, governance) {
        _positionManager = uniV3PositionManager;
    }

    function positionManager() external view returns (INonfungiblePositionManager) {
        return _positionManager;
    }
}
