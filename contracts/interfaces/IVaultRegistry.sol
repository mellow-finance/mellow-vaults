// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IProtocolGovernance.sol";
import "./IVaultFactory.sol";
import "./IVaultGovernance.sol";

interface IVaultRegistry is IERC721 {
    /// @notice Get Vault for the giver NFT ID
    /// @param nftId NFT ID
    /// @return vault Address of the Vault contract
    function vaultForNft(uint256 nftId) external view returns (address vault);

    /// @notice Get NFT ID for given Vault contract address
    /// @param vault Address of the Vault contract
    /// @return nftId NFT ID
    function nftForVault(address vault) external view returns (uint256 nftId);

    /// @notice Register new Vault and mint NFT
    /// @param vault address of the vault
    /// @param owner owner of the NFT
    /// @return nft Nft minted for the given Vault
    function registerVault(address vault, address owner) external returns (uint256 nft);

    /// @notice Number of Vaults registered
    function vaultsCount() external view returns (uint256);

    /// @notice All Vaults registered
    function vaults() external view returns (address[] memory);

    /// @notice Address of the ProtocolGovernance
    function protocolGovernance() external view returns (IProtocolGovernance);

    /// @notice Address of the staged ProtocolGovernance
    function stagedProtocolGovernance() external view returns (IProtocolGovernance);

    /// @notice Minimal timestamp when staged ProtocolGovernance can be applied
    function stagedProtocolGovernanceTimestamp() external view returns (uint256);

    /// @notice Stage new ProtocolGovernance
    /// @param newProtocolGovernance new ProtocolGovernance
    function stageProtocolGovernance(IProtocolGovernance newProtocolGovernance) external;

    /// @notice Comit new ProtocolGovernance
    function commitStagedProtocolGovernance() external;

    /// @notice Emitted when new Vault is registered in VaultRegistry
    /// @param origin Origin of the transaction
    /// @param sender Sender of the transaction
    /// @param nft VaultRegistry NFT of the vault
    /// @param vault Address of the Vault contract
    /// @param owner Owner of the VaultRegistry NFT
    event VaultRegistered(
        address indexed origin,
        address indexed sender,
        uint256 indexed nft,
        address vault,
        address owner
    );

    /// @param origin Origin of the transaction
    /// @param sender Sender of the transaction
    /// @param newProtocolGovernance Address of the new ProtocolGovernance
    /// @param start Timestamp of the start of the new ProtocolGovernance
    event StagedProtocolGovernance(
        address indexed origin,
        address indexed sender,
        IProtocolGovernance newProtocolGovernance,
        uint256 start
    );

    /// @param origin Origin of the transaction
    /// @param sender Sender of the transaction
    /// @param newProtocolGovernance Address of the new ProtocolGovernance that has been committed
    event CommitedProtocolGovernance(
        address indexed origin,
        address indexed sender,
        IProtocolGovernance newProtocolGovernance
    );
}
