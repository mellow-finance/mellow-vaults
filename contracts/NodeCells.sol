// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./access/GovernanceAccessControl.sol";
import "./interfaces/IDelegatedCells.sol";
import "./libraries/Array.sol";
import "./Cells.sol";
import "./PermissionedERC721Receiver.sol";

contract NodeCells is IDelegatedCells, PermissionedERC721Receiver, Cells {
    using SafeERC20 for IERC20;

    struct DelegatedCell {
        uint256 nft;
        address addr;
    }

    mapping(uint256 => DelegatedCell[]) public ownedCells;

    constructor(string memory name, string memory symbol) Cells(name, symbol) {}

    /// -------------------  PUBLIC, VIEW  -------------------

    /// @dev
    /// the contract is to return sorted tokens
    function delegated(uint256 nft)
        public
        view
        override
        returns (address[] memory tokenAddresses, uint256[] memory tokenAmounts)
    {
        address[] memory cellTokens = managedTokens(nft);
        DelegatedCell[] storage cellOwnedCells = ownedCells[nft];
        uint256[] memory res = new uint256[](cellTokens.length);
        for (uint256 i = 0; i < cellOwnedCells.length; i++) {
            DelegatedCell storage cell = cellOwnedCells[i];
            (address[] memory ownedTokens, uint256[] memory ownedAmounts) = IDelegatedCells(cell.addr).delegated(
                cell.nft
            );
            uint256[] memory projectedOwnedAmounts = Array.projectTokenAmounts(cellTokens, ownedTokens, ownedAmounts);
            for (uint256 j = 0; j < projectedOwnedAmounts.length; j++) {
                res[j] += projectedOwnedAmounts[j];
            }
        }
        tokenAddresses = cellTokens;
        tokenAmounts = res;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(Cells, IERC165, AccessControlEnumerable)
        returns (bool)
    {
        return interfaceId == type(ICells).interfaceId || super.supportsInterface(interfaceId);
    }

    /// -------------------  PUBLIC, MUTATING, NFT_OWNER  -------------------

    function deposit(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO");
        require(Array.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == tokenAmounts.length, "L");
        address[] memory cellTokens = managedTokens(nft);
        require(cellTokens.length >= tokens.length, "TL");
        uint256[] memory cellTokenAmounts = Array.projectTokenAmounts(cellTokens, tokens, tokenAmounts);
        DelegatedCell[] storage cellOwnedCells = ownedCells[nft];
        uint256[][] memory delegatedTokenAmounts = _delegatedByCell(nft);
        uint256[][] memory amountsToDeposit = Array.splitAmounts(cellTokenAmounts, delegatedTokenAmounts);
        actualTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(_msgSender(), address(this), tokenAmounts[i]);
        }
        for (uint256 i = 0; i < cellOwnedCells.length; i++) {
            DelegatedCell storage cell = cellOwnedCells[i];
            for (uint256 j = 0; j < tokens.length; j++) {
                /// TODO: not secure, see method _allowTokenIfNecessary
                _allowTokenIfNecessary(cellTokens[j], cell.addr);
            }
            uint256[] memory actualCellAmounts = IDelegatedCells(cell.addr).deposit(
                cell.nft,
                cellTokens,
                amountsToDeposit[i]
            );
            for (uint256 j = 0; j < tokens.length; j++) {
                actualTokenAmounts[j] += actualCellAmounts[j];
            }
        }
        for (uint256 i = 0; i < tokens.length; i++) {
            if (actualTokenAmounts[i] < tokenAmounts[i]) {
                IERC20(tokens[i]).safeTransfer(_msgSender(), tokenAmounts[i] - actualTokenAmounts[i]);
            } 
        }
        emit Deposit(nft, tokens, actualTokenAmounts);
    }

    function withdraw(
        uint256 nft,
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external override returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO");
        require(Array.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == tokenAmounts.length, "L");
        address[] memory cellTokens = managedTokens(nft);
        require(cellTokens.length >= tokens.length, "TL");
        uint256[] memory cellTokenAmounts = Array.projectTokenAmounts(cellTokens, tokens, tokenAmounts);
        DelegatedCell[] storage cellOwnedCells = ownedCells[nft];
        uint256[][] memory delegatedTokenAmounts = _delegatedByCell(nft);
        uint256[][] memory amountsToDeposit = Array.splitAmounts(cellTokenAmounts, delegatedTokenAmounts);
        actualTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < cellOwnedCells.length; i++) {
            uint256[] memory actualCellAmounts = IDelegatedCells(cellOwnedCells[i].addr).withdraw(
                cellOwnedCells[i].nft,
                to,
                cellTokens,
                amountsToDeposit[i]
            );
            for (uint256 j = 0; j < tokens.length; j++) {
                actualTokenAmounts[j] += actualCellAmounts[j];
            }
        }
        emit Withdraw(nft, to, tokens, actualTokenAmounts);
    }

    function transferOwnedNft(
        uint256 nft,
        address ownedNftAddress,
        uint256 ownedNft,
        address to
    ) external {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO");
        DelegatedCell memory delegatedCell = DelegatedCell({addr: ownedNftAddress, nft: ownedNft});
        require(_delegatedCellIsOwned(nft, delegatedCell), "DCO");
        IERC721(ownedNftAddress).safeTransferFrom(address(this), to, ownedNft);
    }

    /// -------------------  PRIVATE, VIEW  -------------------

    function _delegatedCellIsOwned(uint256 nft, DelegatedCell memory externalCell) internal view returns (bool) {
        DelegatedCell[] storage cells = ownedCells[nft];
        for (uint256 i = 0; i < cells.length; i++) {
            if ((externalCell.addr == cells[i].addr) && (externalCell.nft == cells[i].nft)) {
                return true;
            }
        }
        return false;
    }

    /// @dev returns in accordance to cellOwnedCells order. Check if it could be mutated at reentrancy. Actually force it to be immutable.
    function _delegatedByCell(uint256 nft) internal view returns (uint256[][] memory tokenAmounts) {
        address[] memory cellTokens = managedTokens(nft);
        DelegatedCell[] storage cellOwnedCells = ownedCells[nft];
        tokenAmounts = new uint256[][](cellOwnedCells.length);
        for (uint256 i = 0; i < cellOwnedCells.length; i++) {
            DelegatedCell storage cell = cellOwnedCells[i];
            (address[] memory externalCellTokens, uint256[] memory externalCellAmounts) = IDelegatedCells(cell.addr)
                .delegated(cell.nft);
            tokenAmounts[i] = Array.projectTokenAmounts(cellTokens, externalCellTokens, externalCellAmounts);
        }
    }

    /// -------------------  PRIVATE, MUTATING  -------------------
    function _onPermissionedERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) internal override returns (bytes4) {
        require(data.length == 32, "IB");
        uint256 cellNft;
        // TODO: Figure out why calldataload don't need a 32 bytes offset for the bytes length like mload
        // probably due to how .offset works
        assembly {
            cellNft := calldataload(data.offset)
        }
        // Accept only from cell owner / operator
        require(_isApprovedOrOwner(from, cellNft), "IO"); // Also checks that the token exists
        // Approve sender to manage token
        IERC721(_msgSender()).approve(from, tokenId);
        DelegatedCell memory externalCell = DelegatedCell({nft: tokenId, addr: _msgSender()});
        if (!_delegatedCellIsOwned(cellNft, externalCell)) {
            ownedCells[cellNft].push(externalCell);
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    function _allowTokenIfNecessary(address token, address cells) internal {
        // !!! TODO: this is not secure, add whitelist here - WhiteListAllowance contract
        if (IERC20(token).allowance(address(cells), address(this)) < type(uint256).max / 2) {
            IERC20(token).approve(address(cells), type(uint256).max);
        }
    }
}
