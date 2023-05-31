// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./ICamelotVault.sol";
import "./IVaultGovernance.sol";

interface ICamelotVaultGovernance is IVaultGovernance {
    /// @notice Deploys a new vault.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param owner_ Owner of the vault NFT
    /// @param erc20Vault_ address of erc20 vault
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        address erc20Vault_
    ) external returns (ICamelotVault vault, uint256 nft);
}
