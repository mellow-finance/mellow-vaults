// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./access/OwnerAccessControl.sol";
import "./interfaces/ICells.sol";
import "./libraries/Array.sol";

contract NodeCells is ICells, IERC721Receiver, OwnerAccessControl, ERC721 {
    bool isPublicCreateCell;
    uint256 public maxTokensPerCell;
    address[] public nftAllowList;
    mapping(address => bool) public nftAllowListIndex;

    struct ExternalCell {
        uint256 nft;
        address addr;
    }

    mapping(uint256 => ExternalCell[]) public ownedCells;
    mapping(uint256 => address[]) private _managedTokens;
    mapping(uint256 => mapping(address => bool)) public managedTokensIndex;
    uint256 private _topCellNft;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        maxTokensPerCell = 10;
    }

    function managedTokens(uint256 nft) external view override returns (address[] memory) {
        return _managedTokens[nft];
    }

    /// @dev
    /// the contract is to return sorted tokens
    function delegated(uint256 nft)
        public
        view
        override
        returns (address[] memory tokenAddresses, uint256[] memory tokenAmounts)
    {
        address[] storage cellTokens = _managedTokens[nft];
        ExternalCell[] storage cellOwnedCells = ownedCells[nft];
        uint256[] memory res = new uint256[](cellTokens.length);
        for (uint256 i = 0; i < cellOwnedCells.length; i++) {
            ExternalCell storage cell = cellOwnedCells[i];
            (address[] memory ownedTokens, uint256[] memory ownedAmounts) = ICells(cell.addr).delegated(cell.nft);
            uint256[] memory projectedOwnedAmounts = Array.projectTokenAmounts(cellTokens, ownedTokens, ownedAmounts);
            for (uint256 j = 0; j < projectedOwnedAmounts.length; j++) {
                res[j] += projectedOwnedAmounts[j];
            }
        }
        tokenAddresses = cellTokens;
        tokenAmounts = res;
    }

    /// @dev
    /// Requires tokens to be sorted and unique and be a subset fo _managedTokens
    function deposit(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO");
        require(Array.isSortedAndUnique(tokens), "NS");
        address[] storage cellTokens = _managedTokens[nft];
        require(cellTokens.length >= tokens.length, "TL");
        uint256[] memory cellTokenAmounts = Array.projectTokenAmounts(cellTokens, tokens, tokenAmounts);
        ExternalCell[] storage cellOwnedCells = ownedCells[nft];
        uint256[][] memory delegatedTokenAmounts = _delegatedByCell(nft);
        uint256[][] memory amountsToDeposit = Array.splitAmounts(cellTokenAmounts, delegatedTokenAmounts);
        for (uint256 i = 0; i < cellOwnedCells.length; i++) {
            ExternalCell storage cell = cellOwnedCells[i];
            ICells(cell.addr).deposit(cell.nft, cellTokens, amountsToDeposit[i]);
        }
    }

    function withdraw(
        uint256 nft,
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO");
        require(Array.isSortedAndUnique(tokens), "NS");
        address[] storage cellTokens = _managedTokens[nft];
        require(cellTokens.length >= tokens.length, "TL");
        uint256[] memory cellTokenAmounts = Array.projectTokenAmounts(cellTokens, tokens, tokenAmounts);
        ExternalCell[] storage cellOwnedCells = ownedCells[nft];
        uint256[][] memory delegatedTokenAmounts = _delegatedByCell(nft);
        uint256[][] memory amountsToDeposit = Array.splitAmounts(cellTokenAmounts, delegatedTokenAmounts);
        for (uint256 i = 0; i < cellOwnedCells.length; i++) {
            ExternalCell storage cell = cellOwnedCells[i];
            ICells(cell.addr).withdraw(cell.nft, to, cellTokens, amountsToDeposit[i]);
        }
    }

    /// @dev sorts tokens before saving
    function createCell(address[] memory cellTokens) external returns (uint256) {
        require(isPublicCreateCell || hasRole(OWNER_ROLE, _msgSender()), "FB");
        require(cellTokens.length <= maxTokensPerCell, "MT");
        uint256 nft = _topCellNft;
        _topCellNft += 1;
        Array.bubbleSort(cellTokens);
        _managedTokens[nft] = cellTokens;
        for (uint256 i = 0; i < cellTokens.length; i++) {
            managedTokensIndex[nft][cellTokens[i]] = true;
        }
        _safeMint(_msgSender(), nft);
        return nft;
    }

    function releaseNft(address to) external {}

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        // Only a handful of contracts can send nfts here
        // You have to carefully verify that contract sending callback correctly satisfies the ERC721 protocol
        // Most critically so that operator could not be forged
        // Otherwise cells could be flooded with unnecessary nfts
        require(nftAllowListIndex[_msgSender()], "IMS");
        require(data.length == 32, "IB");
        uint256 cellNft;
        assembly {
            cellNft := mload(add(data.offset, 32))
        }
        // Accept only from cell owner / operator
        require(_isApprovedOrOwner(operator, cellNft), "IO"); // Also checks that the token exists
        ExternalCell memory externalCell = ExternalCell({nft: tokenId, addr: _msgSender()});
        if (!_externalCellExists(cellNft, externalCell)) {
            ownedCells[cellNft].push(externalCell);
        }
        return IERC721Receiver.onERC721Received.selector;
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

    function _externalCellExists(uint256 nft, ExternalCell memory externalCell) internal view returns (bool) {
        ExternalCell[] storage cells = ownedCells[nft];
        for (uint256 i = 0; i < cells.length; i++) {
            if ((externalCell.addr == cells[i].addr) && (externalCell.nft == cells[i].nft)) {
                return true;
            }
        }
        return false;
    }

    /// @dev returns in accordance to cellOwnedCells order. Check if it could be mutated at reentrancy. Actually force it to be immutable.
    function _delegatedByCell(uint256 nft) internal view returns (uint256[][] memory tokenAmounts) {
        address[] storage cellTokens = _managedTokens[nft];
        ExternalCell[] storage cellOwnedCells = ownedCells[nft];
        tokenAmounts = new uint256[][](cellOwnedCells.length);
        for (uint256 i = 0; i < cellOwnedCells.length; i++) {
            ExternalCell storage cell = cellOwnedCells[i];
            (address[] memory externalCellTokens, uint256[] memory externalCellAmounts) = ICells(cell.addr).delegated(
                cell.nft
            );
            tokenAmounts[i] = Array.projectTokenAmounts(cellTokens, externalCellTokens, externalCellAmounts);
        }
    }
}
