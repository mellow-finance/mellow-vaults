// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IAggregateVault.sol";

interface IERC20RootVault is IAggregateVault {
    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param strategy_ The address that will have approvals for subvaultNfts
    /// @param subvaultNfts_ The NFTs of the subvaults that will be aggregated by this ERC20RootVault
    /// @param name_ ERC20 Name of the token
    /// @param symbol_ ERC20 Name of the token
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        address strategy_,
        uint256[] memory subvaultNfts_,
        string memory name_,
        string memory symbol_
    ) external;
}
