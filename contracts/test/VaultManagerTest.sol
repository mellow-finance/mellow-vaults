// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/IVault.sol";
import "../VaultManager.sol";

contract VaultManagerTest is VaultManager {
    constructor(
        string memory name,
        string memory symbol,
        IVaultFactory factory,
        IVaultGovernanceFactory governanceFactory,
        bool permissionless,
        IProtocolGovernance protocolGovernance
    ) VaultManager(name, symbol, factory, governanceFactory, permissionless, protocolGovernance) {}

    function mintVaultNft(IVault vault) public returns (uint256) {
        uint256 nft = _mintVaultNft(vault);
        return nft;
    }
}
