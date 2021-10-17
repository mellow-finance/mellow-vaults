// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IVaultGovernanceFactory.sol";
import "./VaultManager.sol";

contract ERC20VaultManager is VaultManager {

    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        IVaultGovernanceFactory goveranceFactory,
        bool permissionless,
        IProtocolGovernance governance
    ) VaultManager(name, symbol, factory, goveranceFactory, permissionless, governance) {}
}
