// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./VaultManager.sol";
import "./AaveVault.sol";

contract AaveVaultFactory is IVaultFactory {
    function deployVault(
        address[] calldata tokens,
        address strategyTreasury,
        bytes calldata
    ) external override returns (address) {
        AaveVault vault = new AaveVault(tokens, IVaultManager(msg.sender), strategyTreasury);
        return address(vault);
    }
}
