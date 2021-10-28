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
    function registerVault(uint256 vaultKindId, bytes calldata options) 
        external 
        returns (IVault vault, uint256 nftId);

    /// @return `true` if VaultRegistry allows anyone to create a Vault, `false` otherwise
    function permissionless() external view returns (bool);

    /// @return Number of Vaults registered
    function vaultsCount() external view returns (uint112);

    /// @return Number of VaultKinds registered
    function vaultKindsCount() external view returns (uint112);

    /// @return Address of the ProtocolGovernance
    function protocolGovernance() external view returns (IProtocolGovernance);

    /// @return Address of the staged ProtocolGovernance
    function stagedProtocolGovernance() external view returns (IProtocolGovernance);

    /// @return Minimal timestamp when staged ProtocolGovernance can be applied
    function stagedProtocolGovernanceTimestamp() external view returns (uint256);

    /// @notice Stage new ProtocolGovernance
    /// @param newProtocolGovernance new ProtocolGovernance
    function stageProtocolGovernance(IProtocolGovernance newProtocolGovernance) external;

    /// @notice Comit new ProtocolGovernance
    function commitStagedProtocolGovernance() external;

    /// @param nftId NFT ID
    /// @param vault Address of the Vault contract
    /// @param sender Address of the sender
    event VaultRegistered(uint256 indexed nftId, IVault vault, address indexed sender);

    /// @param vaultKindId ID of the vault kind
    /// @param vaultKind New VaultKind structure
    /// @param sender Address of the sender
    event VaultKindRegistered(uint256 vaultKindId, VaultKind vaultKind, address sender);

    /// @param sender Address of the sender who staged new ProtocolGovernance
    /// @param newProtocolGovernance Address of the new ProtocolGovernance
    /// @param start Timestamp of the start of the new ProtocolGovernance
    event StagedProtocolGovernance(
        address indexed sender, 
        IProtocolGovernance newProtocolGovernance, 
        uint256 start
    );

    /// @param sender Address of the sender who commited staged ProtocolGovernance
    /// @param newProtocolGovernance Address of the new ProtocolGovernance that has been committed
    event CommitedProtocolGovernance(
        address indexed sender,
        IProtocolGovernance newProtocolGovernance
    );
}
