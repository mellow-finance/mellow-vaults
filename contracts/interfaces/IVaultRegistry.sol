// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IVault.sol";

interface IVaultRegistry is IERC721 {
    /// @notice Register new Vault Group and mint NFT
    /// @param vault Address of the Vault contract
    /// @return nftId of the NFT minted for the given Vault Group
    function registerVault(IVault vault)
        external
        returns
        (uint256 nftId);
    
    /// @notice Get Vault for the giver NFT ID
    /// @param nftId NFT ID
    /// @return vault Address of the Vault contract
    function vaultForNft(uint256 nftId)
        external
        view
        returns
        (IVault vault);
    
    /// @notice Get NFT ID for given Vault contract address
    /// @param vault Address of the Vault contract
    /// @return nftId NFT ID
    function nftForVault(IVault vault)
        external
        view
        returns
        (uint256 nftId);

    /// @param nftId NFT ID
    /// @param vault Address of the Vault contract
    /// @param message Optional message
    event VaultRegistered(uint256 nftId, IVault vault, bytes message);
}
