// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVault.sol";

interface IVaultFactory {
    /// @notice Deploy a new vault.
    /// @param vaultTokens ERC20 tokens under vault management
    /// @param nft NFT of the vault
    /// @param options Reserved additional deploy options. Should be 0x0
    function deployVault(
        address[] memory vaultTokens,
        uint256 nft,
        bytes memory options
    ) external returns (IVault vault);
}
