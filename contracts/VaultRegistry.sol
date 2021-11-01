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
    string public constant ADMIN_ACCESS_REQUIRED = "AD";
    string public constant UNIQUE_CONSTRAINT = "UX";
    string public constant INVALID_TIMESTAMP = "TS";
    string public constant NULL_OR_NOT_INITIALIZED = "NA";

    bool private _permissionless;
    uint112 private _vaultKindsCount;
    uint112 private _vaultsCount;
    uint256 private _stagedProtocolGovernanceTimestamp;
    IProtocolGovernance private _protocolGovernance;
    IProtocolGovernance private _stagedProtocolGovernance;
    IVaultRegistry.VaultKind[] private _vaultKinds;
    IVault[] private _vaults;
    mapping(IVault => uint256) private _nfts;
    mapping(IVault => uint256) private _vaultKindIds;
    mapping(bytes32 => bool) private _registeredVaultKinds;

    /// @notice Constructor
    /// @param name ERC721 token name
    /// @param symbol ERC721 token symbol
    /// @param protocolGovernance_ Reference to ProtocolGovernance
    constructor (
        string memory name,
        string memory symbol,
        bool permissionless_,
        IProtocolGovernance protocolGovernance_
    ) ERC721(name, symbol) {
        _protocolGovernance = protocolGovernance_;
        _permissionless = permissionless_;
    }

    /// @inheritdoc IVaultRegistry
    function vaultKindForId(uint256 vaultKindId) 
        external 
        view 
        returns (IVaultRegistry.VaultKind memory vaultKind) {
        vaultKind = _vaultKinds[vaultKindId];
    }

    /// @inheritdoc IVaultRegistry
    function vaultKindForVault(IVault vault)
        external
        view
        returns (IVaultRegistry.VaultKind memory vaultKind) {
        uint256 vaultKindId = _vaultKindIds[vault];
        vaultKind = _vaultKinds[vaultKindId];
    }

    /// @inheritdoc IVaultRegistry
    function vaultForNft(uint256 nftId) external view returns (IVault vault) {
        require(nftId < _vaultsCount, INDEX_OUT_OF_BOUNDS);
        return _vaults[nftId];
    }

    /// @inheritdoc IVaultRegistry
    function nftForVault(IVault vault) external view returns (uint256 nftId) {
        nftId = _nfts[vault];
    }

    /// @inheritdoc IVaultRegistry
    function registerVaultKind(IVaultRegistry.VaultKind memory vaultKind) 
        external 
        returns (uint256 vaultKindId) {
        bytes32 vaultKindHash = _calcVaultKindHash(vaultKind);
        require(!_registeredVaultKinds[vaultKindHash], UNIQUE_CONSTRAINT);
        require(_isProtocolAdmin(_msgSender()), ADMIN_ACCESS_REQUIRED);
        _saveNewVaultKind(vaultKind);
        _registeredVaultKinds[vaultKindHash] = true;
        emit VaultKindRegistered(vaultKindId, vaultKind, _msgSender());
    }

    /// @inheritdoc IVaultRegistry
    function registerVault(uint256 vaultKindId, bytes calldata options) 
        external 
        returns 
        (IVault vault, uint256 nftId) {
        require(
            _permissionless || _isProtocolAdmin(_msgSender()),
            ADMIN_ACCESS_REQUIRED
        );
        vault = _createNewVault(vaultKindId, options);
        nftId = _saveNewVault(vault);
        _safeMint(_msgSender(), nftId);
        emit VaultRegistered(nftId, vault, _msgSender());
    }

    /// @inheritdoc IVaultRegistry
    function permissionless() external view returns (bool) {
        return _permissionless;
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
    function vaultKindsCount() external view returns (uint112) {
        return _vaultKindsCount;
    }

    /// @inheritdoc IVaultRegistry
    function vaultsCount() external view returns (uint112) {
        return _vaultsCount;
    }

    /// @inheritdoc IVaultRegistry
    function stageProtocolGovernance(IProtocolGovernance newProtocolGovernance) external {
        require(_isProtocolAdmin(_msgSender()), ADMIN_ACCESS_REQUIRED);
        _stagedProtocolGovernance = newProtocolGovernance;
        _stagedProtocolGovernanceTimestamp = (
            block.timestamp + 
            _protocolGovernance.governanceDelay()
        );
        emit StagedProtocolGovernance(
            _msgSender(),
            newProtocolGovernance,
            _stagedProtocolGovernanceTimestamp
        );
    }

    /// @inheritdoc IVaultRegistry
    function commitStagedProtocolGovernance() external {
        require(_isProtocolAdmin(_msgSender()), ADMIN_ACCESS_REQUIRED);
        require(_stagedProtocolGovernanceTimestamp > 0, NULL_OR_NOT_INITIALIZED);
        require(block.timestamp > _stagedProtocolGovernanceTimestamp, INVALID_TIMESTAMP);
        _protocolGovernance = _stagedProtocolGovernance;
        delete _stagedProtocolGovernanceTimestamp;
        emit CommitedProtocolGovernance(_msgSender(), _protocolGovernance);
    }

    function _isProtocolAdmin(address sender) internal view returns (bool) {
        return _protocolGovernance.isAdmin(sender);
    }

    function _saveNewVaultKind(IVaultRegistry.VaultKind memory vaultKind)
        internal 
        returns (uint256 vaultKindId) {
        vaultKindId = _vaultKindsCount;
        _vaultKindsCount++;
        _vaultKinds.push(vaultKind);
    }

    function _saveNewVault(IVault vault) internal returns (uint256 nftId) {
        nftId = _vaultsCount + 1;
        _vaultsCount++;
        _vaults.push(vault);
        _nfts[vault] = nftId;
    }

    function _createNewVault(uint256 vaultKindId, bytes calldata options) 
        internal 
        returns (IVault vault) {
        IVaultRegistry.VaultKind memory vaultKind = _vaultKinds[vaultKindId];
        IVaultFactory vaultFactory = vaultKind.vaultFactory;
        IVaultGovernance vaultGovernance = vaultKind.vaultGovernance;
        vault = vaultFactory.deployVault(vaultGovernance, options);
        _vaultKindIds[vault] = vaultKindId;
    }

    function _calcVaultKindHash(IVaultRegistry.VaultKind memory vaultKind) 
        internal pure 
        returns (bytes32 vaultKindHash) {
        vaultKindHash = keccak256(abi.encode(vaultKind));
    } 
}
