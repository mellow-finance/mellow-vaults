// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./access/GovernanceAccessControl.sol";
import "./interfaces/ICells.sol";
import "./libraries/Array.sol";

contract Cells is ICells, GovernanceAccessControl, ERC721 {
    bool public permissionless = false;
    bool public pendingPermissionless;
    uint256 public maxTokensPerCell = 10;
    uint256 public pendingMaxTokensPerCell;
    mapping(uint256 => address[]) private _managedTokens;
    mapping(uint256 => mapping(address => bool)) private _managedTokensIndex;
    uint256 private _topCellNft = 1;

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
        return interfaceId == type(ICells).interfaceId || super.supportsInterface(interfaceId);
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

    function setPendingMaxTokensPerCell(uint256 _pendingMaxTokensPerCell) external {
        require(_isGovernanceOrDelegate(), "PGD");
        pendingMaxTokensPerCell = _pendingMaxTokensPerCell;
    }

    function commitPendingMaxTokensPerCell() external {
        require(_isGovernanceOrDelegate(), "PGD");
        maxTokensPerCell = pendingMaxTokensPerCell;
        pendingMaxTokensPerCell = 0;
    }

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE OR PERMISSIONLESS  -------------------
    function createCell(address[] memory cellTokens, bytes memory params) external override returns (uint256) {
        require(permissionless || _isGovernanceOrDelegate(), "PGD");
        require(cellTokens.length <= maxTokensPerCell, "MT");
        require(Array.isSortedAndUnique(cellTokens), "SAU");
        uint256 nft = _mintCellNft(cellTokens, params);
        _managedTokens[nft] = cellTokens;
        for (uint256 i = 0; i < cellTokens.length; i++) {
            _managedTokensIndex[nft][cellTokens[i]] = true;
        }
        emit CreateCell(_msgSender(), nft);
        return nft;
    }

    /// -------------------  PRIVATE, MUTATING  -------------------

    function _mintCellNft(address[] memory, bytes memory) internal virtual returns (uint256) {
        uint256 nft = _topCellNft;
        _topCellNft += 1;
        _safeMint(_msgSender(), nft);
        return nft;
    }

    event CreateCell(address indexed to, uint256 indexed nft);
}
