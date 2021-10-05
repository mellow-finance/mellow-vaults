// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultManager.sol";
import "./external/univ3/INonfungiblePositionManager.sol";

interface IUniV3VaultManager is IVaultManager {
    function positionManager() external view returns (INonfungiblePositionManager);
}
