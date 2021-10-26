// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IVault.sol";
import "./IVaultGovernance.sol";
import "./IVaultFactoryV2.sol";
import "./IProtocolGovernance.sol";

interface IVaultRegistry is IERC721 {
    /// @notice VaultKind structure
    /// @param permissionless Is permissionless
    /// @param vaultFactory Address of the vault factory
    /// @param vaultGovernance Address of the vault governance
    /// @param protocolGovernance Address of the protocol governance
    struct VaultKind {
        IVaultFactoryV2 vaultFactory;
        IVaultGovernance vaultGovernance;
    }

    /// @notice Get the address of the VaultFactory and VaultGovernanceOld for the given vault kind
    /// @param vaultKindId ID of the vault kind
    /// @return vaultKind Vault Kind structure
    function vaultKindForId(uint256 vaultKindId) external view returns (VaultKind memory vaultKind);

    /// @notice Get the the vault kind for the given vault address
    /// @param vault Address of the vault
    /// @return vaultKind VaultKind structure
    function vaultKindForVault(IVault vault) external view returns (VaultKind memory vaultKind);

    /// @notice Get Vault for the giver NFT ID
    /// @param nftId NFT ID
    /// @return vault Address of the Vault contract
    function vaultForNft(uint256 nftId) external view returns (IVault vault);

    /// @notice Get NFT ID for given Vault contract address
    /// @param vault Address of the Vault contract
    /// @return nftId NFT ID
    function nftForVault(IVault vault) external view returns (uint256 nftId);

    /// @notice Register a new vault kind
    /// @param vaultKind VaultKind structure
    /// @return vaultKindId ID of the new vault kind
    function registerVaultKind(VaultKind calldata vaultKind) 
        external
        returns (uint256 vaultKindId);

    /// @notice Register new Vault and mint NFT
    /// @param vaultKindId ID of the vault kind
    /// @return vault Address of created Vault
    /// @return nftId ID the NFT minted for the given Vault Group
    function registerVault(uint256 vaultKindId, bytes calldata options) external returns (IVault vault, uint256 nftId);

    /// @param nftId NFT ID
    /// @param vault Address of the Vault contract
    /// @param sender Address of the sender
    event VaultRegistered(uint256 nftId, IVault vault, address sender);

    /// @param vaultKindId ID of the vault kind
    /// @param vaultKind New VaultKind structure
    /// @param sender Address of the sender
    event VaultKindRegistered(uint256 vaultKindId, VaultKind vaultKind, address sender);
}
