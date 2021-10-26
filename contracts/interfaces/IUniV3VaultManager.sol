// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultManager.sol";
import "./external/univ3/INonfungiblePositionManager.sol";

interface IUniV3VaultManager is IVaultManager {
    /// @notice Referenc to UniV3 nonfungible position manager
    function positionManager() external view returns (INonfungiblePositionManager);
}
