// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IMellowVault.sol";
import "./IVaultGovernance.sol";

interface IMellowVaultGovernance is IVaultGovernance {
    /// @notice Deploys a new vault.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param owner_ Owner of the vault NFT
    /// @param underlyingVault Underlying mellow vault
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        IERC20RootVault underlyingVault
    ) external returns (IMellowVault vault, uint256 nft);
}
