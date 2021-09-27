// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./access/GovernanceAccessControl.sol";
import "./interfaces/IVaults.sol";
import "./libraries/Array.sol";

contract Vaults is IVaults, GovernanceAccessControl, ERC721 {
    bool public permissionless = false;
    bool public pendingPermissionless;
    uint256 public maxTokensPerVault = 10;
    uint256 public pendingMaxTokensPerVault;
    mapping(uint256 => address[]) private _managedTokens;
    mapping(uint256 => mapping(address => bool)) private _managedTokensIndex;
    uint256 private _topVaultNft = 1;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    /// -------------------  PUBLIC, VIEW  -------------------

    function managedTokens(uint256 nft) public view override returns (address[] memory) {
        return _managedTokens[nft];
    }

    function isManagedToken(uint256 nft, address token) public view override returns (bool) {
        return _managedTokensIndex[nft][token];
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, IERC165, AccessControlEnumerable)
        returns (bool)
    {
        return interfaceId == type(IVaults).interfaceId || super.supportsInterface(interfaceId);
    }

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE  -------------------

    function setPendingPermissionless(bool _pendingPermissionless) external {
        require(_isGovernanceOrDelegate(), "PGD");
        pendingPermissionless = _pendingPermissionless;
    }

    function commitPendingPermissionless() external {
        require(_isGovernanceOrDelegate(), "PGD");
        permissionless = pendingPermissionless;
        pendingPermissionless = false;
    }

    function setPendingMaxTokensPerVault(uint256 _pendingMaxTokensPerVault) external {
        require(_isGovernanceOrDelegate(), "PGD");
        pendingMaxTokensPerVault = _pendingMaxTokensPerVault;
    }

    function commitPendingMaxTokensPerVault() external {
        require(_isGovernanceOrDelegate(), "PGD");
        maxTokensPerVault = pendingMaxTokensPerVault;
        pendingMaxTokensPerVault = 0;
    }

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE OR PERMISSIONLESS  -------------------
    function createVault(address[] memory cellTokens, bytes memory params) external override returns (uint256) {
        require(permissionless || _isGovernanceOrDelegate(), "PGD");
        require(cellTokens.length <= maxTokensPerVault, "MT");
        require(Array.isSortedAndUnique(cellTokens), "SAU");
        uint256 nft = _mintVaultNft(cellTokens, params);
        _managedTokens[nft] = cellTokens;
        for (uint256 i = 0; i < cellTokens.length; i++) {
            _managedTokensIndex[nft][cellTokens[i]] = true;
        }
        emit IVaults.CreateVault(_msgSender(), nft, params);
        return nft;
    }

    /// -------------------  PRIVATE, MUTATING  -------------------

    function _mintVaultNft(address[] memory, bytes memory) internal virtual returns (uint256) {
        uint256 nft = _topVaultNft;
        _topVaultNft += 1;
        _safeMint(_msgSender(), nft);
        return nft;
    }
}
