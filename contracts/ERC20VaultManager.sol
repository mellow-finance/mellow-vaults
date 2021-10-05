// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./VaultManager.sol";
import "./ERC20Vault.sol";

contract ERC20VaultManager is VaultManager {
    constructor(
        string memory name,
        string memory symbol,
        bool permissionless,
        IProtocolGovernance governance
    ) VaultManager(name, symbol, permissionless, governance) {}

    function _deployVault(address[] memory tokens, uint256[] memory limits) internal override returns (address) {
        ERC20Vault vault = new ERC20Vault(tokens, limits, this);
        return address(vault);
    }
}
