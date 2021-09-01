// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./access/OwnerAccessControl.sol";
import "./interfaces/ICells.sol";
import "./libraries/Array.sol";

contract Cells is ICells, OwnerAccessControl, ERC721 {
    bool isPublicCreateCell;
    uint256 public maxTokensPerCell;
    mapping(uint256 => address[]) private _managedTokens;
    mapping(uint256 => mapping(address => bool)) private _managedTokensIndex;
    uint256 private _topCellNft;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        maxTokensPerCell = 10;
    }

    function managedTokens(uint256 nft) public view override returns (address[] memory) {
        return _managedTokens[nft];
    }

    function isManagedToken(uint256 nft, address token) public view override returns (bool) {
        return _managedTokensIndex[nft][token];
    }

    function createCell(address[] memory cellTokens, bytes memory) external virtual override returns (uint256) {
        require(isPublicCreateCell || hasRole(OWNER_ROLE, _msgSender()), "FB");
        require(cellTokens.length <= maxTokensPerCell, "MT");
        uint256 nft = _topCellNft;
        _topCellNft += 1;
        Array.bubbleSort(cellTokens);
        _managedTokens[nft] = cellTokens;
        for (uint256 i = 0; i < cellTokens.length; i++) {
            _managedTokensIndex[nft][cellTokens[i]] = true;
        }
        _safeMint(_msgSender(), nft);
        return nft;
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
}
