// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IVaultRegistry.sol";

/// @notice This contract is used to deploy the Vault contract and mint NFT for it.
contract VaultRegistry is IVaultRegistry, ERC721 {
    string public constant INDEX_OUT_OF_BOUNDS = "ID";
    string public constant PROTOCOL_ADMIN = "ADM";
    string public constant UNIQUE_CONSTRAINT = "UX";
    string public constant INVALID_TIMESTAMP = "TS";
    string public constant NULL_OR_NOT_INITIALIZED = "NA";

    uint256 private _stagedProtocolGovernanceTimestamp;
    IProtocolGovernance private _protocolGovernance;
    IProtocolGovernance private _stagedProtocolGovernance;

    address[] private _vaults;
    mapping(address => uint256) private _nftIndex;
    mapping(uint256 => address) private _vaultIndex;
    uint256 private _topNft = 1;

    /// @notice Constructor
    /// @param name ERC721 token name
    /// @param symbol ERC721 token symbol
    /// @param protocolGovernance_ Reference to ProtocolGovernance
    constructor(
        string memory name,
        string memory symbol,
        IProtocolGovernance protocolGovernance_
    ) ERC721(name, symbol) {
        _protocolGovernance = protocolGovernance_;
    }

    function vaults() external view returns (address[] memory) {
        return _vaults;
    }

    /// @inheritdoc IVaultRegistry
    function vaultForNft(uint256 nft) external view returns (address) {
        return _vaultIndex[nft];
    }

    /// @inheritdoc IVaultRegistry
    function nftForVault(address vault) external view returns (uint256) {
        return _nftIndex[vault];
    }

    /// @inheritdoc IVaultRegistry
    function registerVault(address vault, address owner) external returns (uint256 nft) {
        require(_protocolGovernance.isVaultGovernance(msg.sender), PROTOCOL_ADMIN);
        nft = _topNft;
        _safeMint(owner, nft);
        _vaultIndex[nft] = vault;
        _nftIndex[vault] = nft;
        _vaults.push(vault);
        _topNft += 1;
        emit VaultRegistered(tx.origin, msg.sender, nft, vault, owner);
    }

    /// @inheritdoc IVaultRegistry
    function protocolGovernance() external view returns (IProtocolGovernance) {
        return _protocolGovernance;
    }

    /// @inheritdoc IVaultRegistry
    function stagedProtocolGovernance() external view returns (IProtocolGovernance) {
        return _stagedProtocolGovernance;
    }

    /// @inheritdoc IVaultRegistry
    function stagedProtocolGovernanceTimestamp() external view returns (uint256) {
        return _stagedProtocolGovernanceTimestamp;
    }

    /// @inheritdoc IVaultRegistry
    function vaultsCount() external view returns (uint256) {
        return _vaults.length;
    }

    /// @inheritdoc IVaultRegistry
    function stageProtocolGovernance(IProtocolGovernance newProtocolGovernance) external {
        require(_isProtocolAdmin(_msgSender()), PROTOCOL_ADMIN);
        _stagedProtocolGovernance = newProtocolGovernance;
        _stagedProtocolGovernanceTimestamp = (block.timestamp + _protocolGovernance.governanceDelay());
        emit StagedProtocolGovernance(tx.origin, msg.sender, newProtocolGovernance, _stagedProtocolGovernanceTimestamp);
    }

    /// @inheritdoc IVaultRegistry
    function commitStagedProtocolGovernance() external {
        require(_isProtocolAdmin(_msgSender()), PROTOCOL_ADMIN);
        require(_stagedProtocolGovernanceTimestamp > 0, NULL_OR_NOT_INITIALIZED);
        require(block.timestamp > _stagedProtocolGovernanceTimestamp, INVALID_TIMESTAMP);
        _protocolGovernance = _stagedProtocolGovernance;
        delete _stagedProtocolGovernanceTimestamp;
        emit CommitedProtocolGovernance(tx.origin, msg.sender, _protocolGovernance);
    }

    function _isProtocolAdmin(address sender) internal view returns (bool) {
        return _protocolGovernance.isAdmin(sender);
    }
}
