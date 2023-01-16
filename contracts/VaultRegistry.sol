// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/vaults/IVault.sol";
import "./interfaces/IVaultRegistry.sol";
import "./libraries/ExceptionsLibrary.sol";
import "./libraries/PermissionIdsLibrary.sol";
import "./utils/ContractMeta.sol";

/// @notice This contract is used to manage ERC721 NFT for all Vaults.
contract VaultRegistry is ContractMeta, IVaultRegistry, ERC721 {
    uint256 private _stagedProtocolGovernanceTimestamp;
    IProtocolGovernance private _protocolGovernance;
    IProtocolGovernance private _stagedProtocolGovernance;

    address[] private _vaults;
    mapping(address => uint256) private _nftIndex;
    mapping(uint256 => address) private _vaultIndex;
    mapping(uint256 => bool) private _locks;
    uint256 private _topNft = 1;

    /// @notice Creates a new contract.
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

    // -------------------  EXTERNAL, VIEW  -------------------

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
    function isLocked(uint256 nft) external view returns (bool) {
        return _locks[nft];
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

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId) || type(IVaultRegistry).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IVaultRegistry
    function registerVault(address vault, address owner) external returns (uint256 nft) {
        require(address(owner) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        require(ERC165(vault).supportsInterface(type(IVault).interfaceId), ExceptionsLibrary.INVALID_INTERFACE);
        require(
            _protocolGovernance.hasPermission(msg.sender, PermissionIdsLibrary.REGISTER_VAULT),
            ExceptionsLibrary.FORBIDDEN
        );
        require(_nftIndex[vault] == 0, ExceptionsLibrary.DUPLICATE);
        nft = _topNft;
        _vaultIndex[nft] = vault;
        _nftIndex[vault] = nft;
        _vaults.push(vault);
        _topNft += 1;
        _safeMint(owner, nft);
        emit VaultRegistered(tx.origin, msg.sender, nft, vault, owner);
    }

    /// @inheritdoc IVaultRegistry
    function stageProtocolGovernance(IProtocolGovernance newProtocolGovernance) external {
        require(_isProtocolAdmin(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(address(newProtocolGovernance) != address(0), ExceptionsLibrary.ADDRESS_ZERO);
        _stagedProtocolGovernance = newProtocolGovernance;
        _stagedProtocolGovernanceTimestamp = (block.timestamp + _protocolGovernance.governanceDelay());
        emit StagedProtocolGovernance(tx.origin, msg.sender, newProtocolGovernance, _stagedProtocolGovernanceTimestamp);
    }

    /// @inheritdoc IVaultRegistry
    function commitStagedProtocolGovernance() external {
        require(_isProtocolAdmin(msg.sender), ExceptionsLibrary.FORBIDDEN);
        require(_stagedProtocolGovernanceTimestamp != 0, ExceptionsLibrary.INIT);
        require(block.timestamp >= _stagedProtocolGovernanceTimestamp, ExceptionsLibrary.TIMESTAMP);
        _protocolGovernance = _stagedProtocolGovernance;
        delete _stagedProtocolGovernanceTimestamp;
        delete _stagedProtocolGovernance;
        emit CommitedProtocolGovernance(tx.origin, msg.sender, _protocolGovernance);
    }

    function lockNft(uint256 nft) external {
        require(ownerOf(nft) == msg.sender, ExceptionsLibrary.FORBIDDEN);
        _locks[nft] = true;
        emit TokenLocked(tx.origin, msg.sender, nft);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("VaultRegistry");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    function _isProtocolAdmin(address sender) internal view returns (bool) {
        return _protocolGovernance.isAdmin(sender);
    }

    function _beforeTokenTransfer(
        address,
        address,
        uint256 tokenId
    ) internal view override {
        require(!_locks[tokenId], ExceptionsLibrary.LOCK);
    }

    // --------------------------  EVENTS  --------------------------

    /// @notice Emitted when token is locked for transfers
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param nft NFT to be locked
    event TokenLocked(address indexed origin, address indexed sender, uint256 indexed nft);

    /// @notice Emitted when new Vault is registered in VaultRegistry
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
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

    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param newProtocolGovernance Address of the new ProtocolGovernance
    /// @param start Timestamp of the start of the new ProtocolGovernance
    event StagedProtocolGovernance(
        address indexed origin,
        address indexed sender,
        IProtocolGovernance newProtocolGovernance,
        uint256 start
    );

    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param newProtocolGovernance Address of the new ProtocolGovernance that has been committed
    event CommitedProtocolGovernance(
        address indexed origin,
        address indexed sender,
        IProtocolGovernance newProtocolGovernance
    );
}
