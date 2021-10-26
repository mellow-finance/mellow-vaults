// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IVault.sol";
import "./IVaultFactory.sol";
import "./IProtocolGovernance.sol";

interface IVaultRegistry is IERC721 {
    /// @notice Register a new vault kind
    /// @param vaultFactory Address of the VaultFactory
    /// @param vaultGovernance Address of the VaultGovernance
    /// @return vaultKind ID of the new vault kind
    function registerVaultKind (
        IVaultFactory vaultFactory,
        IVaultGovernance vaultGovernance
    ) 
        external
        returns (uint256 vaultKind);

    /// @notice Get the address of the VaultFactory and VaultGovernance for the given vault kind
    /// @param vaultKind ID of the vault kind
    /// @return vaultFactory address
    /// @return vaultGovernance address
    function vaultKind(uint256 vaultKind) 
        external view 
        returns (
            IVaultFactory vaultFactory,
            IVaultGovernance vaultGovernance
        );

    /// @notice Register new Vault and mint NFT
    /// @param vaultKind ID of the vault kind
    /// @return vault Address of created Vault
    /// @return nftId ID the NFT minted for the given Vault Group
    function createVault(uint256 vaultKind) 
        external 
        returns (
            IVault vault,
            uint256 nftId
        );
    
    /// @notice Get Vault for the giver NFT ID
    /// @param nftId NFT ID
    /// @return vault Address of the Vault contract
    function vaultForNft(uint256 nftId)
        external view
        returns (IVault vault);
    
    /// @notice Get NFT ID for given Vault contract address
    /// @param vault Address of the Vault contract
    /// @return nftId NFT ID
    function nftForVault(IVault vault)
        external view
        returns (uint256 nftId);

    /// @param nftId NFT ID
    /// @param vault Address of the Vault contract
    /// @param message Optional message
    event VaultRegistered(uint256 nftId, IVault vault, bytes message);
}
