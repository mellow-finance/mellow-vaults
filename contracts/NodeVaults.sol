// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./access/GovernanceAccessControl.sol";
import "./interfaces/IDelegatedVaults.sol";
import "./libraries/Array.sol";
import "./Vaults.sol";
import "./PermissionedERC721Receiver.sol";

contract NodeVaults is IDelegatedVaults, PermissionedERC721Receiver, Vaults {
    using SafeERC20 for IERC20;

    struct DelegatedVault {
        uint256 nft;
        address addr;
    }

    mapping(uint256 => DelegatedVault[]) public ownedVaults;

    constructor(string memory name, string memory symbol) Vaults(name, symbol) {}

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
        DelegatedVault[] storage cellOwnedVaults = ownedVaults[nft];
        uint256[] memory res = new uint256[](cellTokens.length);
        for (uint256 i = 0; i < cellOwnedVaults.length; i++) {
            DelegatedVault storage cell = cellOwnedVaults[i];
            (address[] memory ownedTokens, uint256[] memory ownedAmounts) = IDelegatedVaults(cell.addr).delegated(
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
        override(Vaults, IERC165, AccessControlEnumerable)
        returns (bool)
    {
        return interfaceId == type(IVaults).interfaceId || super.supportsInterface(interfaceId);
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
        DelegatedVault[] storage cellOwnedVaults = ownedVaults[nft];
        uint256[][] memory delegatedTokenAmounts = _delegatedByVault(nft);
        uint256[][] memory amountsToDeposit = Array.splitAmounts(cellTokenAmounts, delegatedTokenAmounts);
        actualTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransferFrom(_msgSender(), address(this), tokenAmounts[i]);
        }
        for (uint256 i = 0; i < cellOwnedVaults.length; i++) {
            DelegatedVault storage cell = cellOwnedVaults[i];
            for (uint256 j = 0; j < tokens.length; j++) {
                /// TODO: not secure, see method _allowTokenIfNecessary
                _allowTokenIfNecessary(cellTokens[j], cell.addr);
            }
            uint256[] memory actualVaultAmounts = IDelegatedVaults(cell.addr).deposit(
                cell.nft,
                cellTokens,
                amountsToDeposit[i]
            );
            for (uint256 j = 0; j < tokens.length; j++) {
                actualTokenAmounts[j] += actualVaultAmounts[j];
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
        DelegatedVault[] storage cellOwnedVaults = ownedVaults[nft];
        uint256[][] memory delegatedTokenAmounts = _delegatedByVault(nft);
        uint256[][] memory amountsToDeposit = Array.splitAmounts(cellTokenAmounts, delegatedTokenAmounts);
        actualTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < cellOwnedVaults.length; i++) {
            uint256[] memory actualVaultAmounts = IDelegatedVaults(cellOwnedVaults[i].addr).withdraw(
                cellOwnedVaults[i].nft,
                to,
                cellTokens,
                amountsToDeposit[i]
            );
            for (uint256 j = 0; j < tokens.length; j++) {
                actualTokenAmounts[j] += actualVaultAmounts[j];
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
        DelegatedVault memory delegatedVault = DelegatedVault({addr: ownedNftAddress, nft: ownedNft});
        require(_delegatedVaultIsOwned(nft, delegatedVault), "DCO");
        IERC721(ownedNftAddress).safeTransferFrom(address(this), to, ownedNft);
    }

    /// -------------------  PRIVATE, VIEW  -------------------

    function _delegatedVaultIsOwned(uint256 nft, DelegatedVault memory externalVault) internal view returns (bool) {
        DelegatedVault[] storage cells = ownedVaults[nft];
        for (uint256 i = 0; i < cells.length; i++) {
            if ((externalVault.addr == cells[i].addr) && (externalVault.nft == cells[i].nft)) {
                return true;
            }
        }
        return false;
    }

    /// @dev returns in accordance to cellOwnedVaults order. Check if it could be mutated at reentrancy. Actually force it to be immutable.
    function _delegatedByVault(uint256 nft) internal view returns (uint256[][] memory tokenAmounts) {
        address[] memory cellTokens = managedTokens(nft);
        DelegatedVault[] storage cellOwnedVaults = ownedVaults[nft];
        tokenAmounts = new uint256[][](cellOwnedVaults.length);
        for (uint256 i = 0; i < cellOwnedVaults.length; i++) {
            DelegatedVault storage cell = cellOwnedVaults[i];
            (address[] memory externalVaultTokens, uint256[] memory externalVaultAmounts) = IDelegatedVaults(cell.addr)
                .delegated(cell.nft);
            tokenAmounts[i] = Array.projectTokenAmounts(cellTokens, externalVaultTokens, externalVaultAmounts);
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
        DelegatedVault memory externalVault = DelegatedVault({nft: tokenId, addr: _msgSender()});
        if (!_delegatedVaultIsOwned(cellNft, externalVault)) {
            ownedVaults[cellNft].push(externalVault);
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
