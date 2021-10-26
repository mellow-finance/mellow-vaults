// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultFactoryV2.sol";
import "./interfaces/IVaultRegistry.sol";
import "./interfaces/IVaultGovernanceFactory.sol";
import "./interfaces/IProtocolGovernance.sol";

// TODO: maybe use ERC721Enumerable
contract VaultRegistry is IVaultRegistry, ERC721 {
    string public constant INDEX_OUT_OF_BOUNDS = "ID";

    IProtocolGovernance private _protocolGovernance;

    uint256 private _vaultKindsCount;
    IVaultRegistry.VaultKind[] private _vaultKinds;

    uint256 _vaultsCount;
    IVault[] private _vaults;
    mapping(IVault => uint256) private _nfts;
    mapping(IVault => uint256) private _vaultKindIds;

    /// @notice Constructor
    /// @param name ERC721 token name
    /// @param symbol ERC721 token symbol
    /// @param protocolGovernance Reference to ProtocolGovernance
    constructor (
        string memory name,
        string memory symbol,
        IProtocolGovernance protocolGovernance
    ) ERC721(name, symbol) {
        _protocolGovernance = protocolGovernance;
    }

    /// @inheritdoc IVaultRegistry
    function vaultKindForId(uint256 vaultKindId) 
        external 
        view 
        returns 
        (IVaultRegistry.VaultKind memory vaultKind) {
        vaultKind = _vaultKinds[vaultKindId];
    }

    /// @inheritdoc IVaultRegistry
    function vaultKindForVault(IVault vault) external view returns (IVaultRegistry.VaultKind memory vaultKind) {
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
        _saveNewVaultKind(vaultKind);
        emit VaultKindRegistered(vaultKindId, vaultKind, _msgSender());
    }

    /// @inheritdoc IVaultRegistry
    function registerVault(uint256 vaultKindId, bytes calldata options) 
        external 
        returns 
        (IVault vault, uint256 nftId) {
        vault = _createNewVault(vaultKindId, options);
        nftId = _saveNewVault(vault);
        _safeMint(_msgSender(), nftId);
        emit VaultRegistered(nftId, vault, _msgSender());
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

    function _createNewVault(uint256 vaultKindId, bytes calldata options) internal returns (IVault vault) {
        IVaultRegistry.VaultKind memory vaultKind = _vaultKinds[vaultKindId];
        IVaultFactoryV2 vaultFactory = vaultKind.vaultFactory;
        IVaultGovernance vaultGovernance = vaultKind.vaultGovernance;
        vault = vaultFactory.deployVault(vaultGovernance, options);
        _vaultKindIds[vault] = vaultKindId;
    }
}
