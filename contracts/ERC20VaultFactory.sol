// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./interfaces/IVaultFactory.sol";
import "./VaultManager.sol";
import "./ERC20Vault.sol";

contract ERC20VaultFactory is IVaultFactory {
    function deployVault(
        address[] calldata tokens,
        address strategyTreasury,
        address admin,
        bytes calldata
    ) external override returns (address) {
        ERC20Vault vault = new ERC20Vault(tokens, IVaultManager(msg.sender), strategyTreasury, admin);
        return address(vault);
    }
}
