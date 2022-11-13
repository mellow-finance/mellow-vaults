// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20Vault.sol";
import "./IVaultGovernance.sol";

interface IERC20VaultGovernance is IVaultGovernance {
    /// @notice Deploys a new vault.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param owner_ Owner of the vault NFT
    function createVault(address[] memory vaultTokens_, address owner_)
        external
        returns (IERC20Vault vault, uint256 nft);
}
