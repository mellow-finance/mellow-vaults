// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultManager.sol";
import "./external/aave/ILendingPool.sol";

interface IAaveVaultManager is IVaultManager {
    function lendingPool() external view returns (ILendingPool);
}
