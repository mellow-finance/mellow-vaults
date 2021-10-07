// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IAaveVaultManager.sol";
import "./interfaces/external/aave/ILendingPool.sol";
import "./VaultManager.sol";

contract AaveVaultManager is IAaveVaultManager, VaultManager {
    ILendingPool _lendingPool;

    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        bool permissionless,
        IProtocolGovernance governance,
        ILendingPool pool
    ) VaultManager(name, symbol, factory, permissionless, governance) {
        _lendingPool = pool;
    }

    function lendingPool() external view returns (ILendingPool) {
        return _lendingPool;
    }
}
