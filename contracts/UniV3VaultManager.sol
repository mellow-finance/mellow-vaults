// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./VaultManager.sol";
import "./UniV3Vault.sol";

contract UniV3VaultManager is VaultManager {
    INonfungiblePositionManager private _positionManager;

    constructor(
        string memory name,
        string memory symbol,
        bool permissionless,
        IProtocolGovernance governance,
        INonfungiblePositionManager _uniV3positionManager
    ) VaultManager(name, symbol, permissionless, governance) {
        _positionManager = _uniV3positionManager;
    }

    function positionManager() external view returns (INonfungiblePositionManager) {
        return _positionManager;
    }

    function _deployVault(address[] memory tokens, uint256[] memory limits) internal override returns (address) {
        ERC20Vault vault = new UniV3Vault(tokens, limits, this, _positionManager);
        return address(vault);
    }
}
