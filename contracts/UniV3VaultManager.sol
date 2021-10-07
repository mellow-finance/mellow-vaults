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

    function _deployVault(
        address[] calldata tokens,
        uint256[] calldata limits,
        bytes calldata options
    ) internal override returns (address) {
        uint256 fee;
        // TODO: Figure out why calldataload don't need a 32 bytes offset for the bytes length like mload
        // probably due to how .offset works
        assembly {
            fee := calldataload(options.offset)
        }
        UniV3Vault vault = new UniV3Vault(tokens, limits, this, uint24(fee));

        return address(vault);
    }
}
