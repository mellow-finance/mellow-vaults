// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract AggregateCells is IERC721Receiver, ERC721 {
    bool isPublicCreateCell;
    address[] public nftAllowList;
    mapping(address => bool) public nftAllowListIndex;

    struct ExternalCell {
        uint256 nft;
        address addr;
    }

    mapping(uint256 => ExternalCell[]) public ownedCells;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function deposit(
        uint256 nft,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) external {}

    function withdraw(
        uint256 nft,
        address to,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) external {}

    function createCell(address[] memory cellTokens) external returns (uint256) {}

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
        require(mutableDelegatedCellsGovernanceParams.nftAllowListIndex[_msgSender()], "IMS");
        require(data.length == 32, "IB");
        uint256 cellNft;
        assembly {
            cellNft := mload(add(data.offset, 32))
        }
        // Accept only from cell owner / operator
        require(_isApprovedOrOwner(operator, cellNft), "IO"); // Also checks that the token exists
        DelegatedCell memory delegatedCell = DelegatedCell({delegatedCellNft: tokenId, addr: _msgSender()});
        if (!_delegatedCellExists(cellNft, delegatedCell)) {
            ownedCells[cellNft].push(delegatedCell);
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    function _delegatedCellExists(uint256 cellNft, ExternalCell memory delegatedCell) private view returns (bool) {
        DelegatedCell[] storage cells = ownedCells[cellNft];
        for (uint256 i = 0; i < cells.length; i++) {
            if (
                (cells[i].delegatedCellNft == delegatedCell.delegatedCellNft) && (cells[i].addr == delegatedCell.addr)
            ) {
                return true;
            }
        }
        return false;
    }
}
