// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./access/GovernanceAccessControl.sol";
import "./libraries/Array.sol";
import "./Vaults.sol";

contract RouterVaults is IERC721Receiver, Vaults {
    /// TODO: add public vaults list
    using SafeERC20 for IERC20;

    struct SubVault {
        uint256 nft;
        address addr;
    }

    mapping(uint256 => SubVault[]) public subVaultsIndex;

    constructor(
        string memory name,
        string memory symbol,
        address _protocolGovernance
    ) Vaults(name, symbol, _protocolGovernance) {}

    /// -------------------  PUBLIC, VIEW  -------------------

    /// @dev
    /// the contract is to return sorted tokens
    function vaultTVL(uint256 nft)
        public
        view
        override
        returns (address[] memory tokens, uint256[] memory tokenAmounts)
    {
        tokens = managedTokens(nft);
        SubVault[] storage subVaults = subVaultsIndex[nft];
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < subVaults.length; i++) {
            SubVault storage subVault = subVaults[i];
            (address[] memory subVaultTokens, uint256[] memory subVaultAmounts) = IVaults(subVault.addr).vaultTVL(
                subVault.nft
            );
            uint256[] memory projectedSubVaultAmounts = Array.projectTokenAmounts(
                tokens,
                subVaultTokens,
                subVaultAmounts
            );
            for (uint256 j = 0; j < projectedSubVaultAmounts.length; j++) {
                tokenAmounts[j] += projectedSubVaultAmounts[j];
            }
        }
    }

    function transferSubVault(
        uint256 nft,
        address subVaultAddress,
        uint256 subVaultNft,
        address to
    ) external {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO");
        SubVault memory delegatedVault = SubVault({addr: subVaultAddress, nft: subVaultNft});
        require(_delegatedVaultIsOwned(nft, delegatedVault), "DCO");
        IERC721(subVaultAddress).safeTransferFrom(address(this), to, subVaultNft);
    }

    /// -------------------  PRIVATE, VIEW  -------------------

    function _delegatedVaultIsOwned(uint256 nft, SubVault memory externalVault) internal view returns (bool) {
        SubVault[] storage vaults = subVaultsIndex[nft];
        for (uint256 i = 0; i < vaults.length; i++) {
            if ((externalVault.addr == vaults[i].addr) && (externalVault.nft == vaults[i].nft)) {
                return true;
            }
        }
        return false;
    }

    /// @dev returns in accordance to vaultOwnedVaults order. Check if it could be mutated at reentrancy. Actually force it to be immutable.
    function _subvaultsTVL(uint256 nft) internal view returns (uint256[][] memory tokenAmounts) {
        address[] memory tokens = managedTokens(nft);
        SubVault[] storage subVaults = subVaultsIndex[nft];
        tokenAmounts = new uint256[][](subVaults.length);
        for (uint256 i = 0; i < subVaults.length; i++) {
            SubVault storage vault = subVaults[i];
            (address[] memory externalVaultTokens, uint256[] memory externalVaultAmounts) = IVaults(vault.addr)
                .vaultTVL(vault.nft);
            tokenAmounts[i] = Array.projectTokenAmounts(tokens, externalVaultTokens, externalVaultAmounts);
        }
    }

    /// -------------------  PRIVATE, MUTATING  -------------------

    function _push(
        uint256 nft,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        SubVault[] storage subVaults = subVaultsIndex[nft];
        uint256[][] memory subVaultTokenAmounts = _subvaultsTVL(nft);
        uint256[][] memory amountsToPush = Array.splitAmounts(tokenAmounts, subVaultTokenAmounts);
        actualTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < subVaults.length; i++) {
            SubVault storage subVault = subVaults[i];
            for (uint256 j = 0; j < tokens.length; j++) {
                /// TODO: not secure, see method _allowTokenIfNecessary
                _allowTokenIfNecessary(tokens[j], subVault.addr);
            }
            /// TODO: can be optimised by grouping positions
            uint256[] memory actualVaultAmounts = IVaults(subVault.addr).transferAndPush(
                subVault.nft,
                address(this),
                tokens,
                amountsToPush[i]
            );
            for (uint256 j = 0; j < tokens.length; j++) {
                actualTokenAmounts[j] += actualVaultAmounts[j];
            }
        }
    }

    /// Guaranteed to have exact signature matching managed tokens
    function _pull(
        uint256 nft,
        address to,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        SubVault[] storage subVaults = subVaultsIndex[nft];
        uint256[][] memory delegatedTokenAmounts = _subvaultsTVL(nft);
        uint256[][] memory amountsToPull = Array.splitAmounts(tokenAmounts, delegatedTokenAmounts);
        actualTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < subVaults.length; i++) {
            uint256[] memory actualVaultAmounts = IVaults(subVaults[i].addr).pull(
                subVaults[i].nft,
                to,
                tokens,
                amountsToPull[i]
            );
            for (uint256 j = 0; j < tokens.length; j++) {
                actualTokenAmounts[j] += actualVaultAmounts[j];
            }
        }
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        require(data.length == 32, "IB");
        uint256 vaultNft;
        // TODO: Figure out why calldataload don't need a 32 bytes offset for the bytes length like mload
        // probably due to how .offset works
        assembly {
            vaultNft := calldataload(data.offset)
        }
        // Accept only from vault owner / operator
        require(_isApprovedOrOwner(from, vaultNft), "IO"); // Also checks that the token exists
        require(protocolGovernance.isAllowedToPull(operator), "AP");
        // Approve sender to manage token
        IERC721(_msgSender()).approve(from, tokenId);
        SubVault memory externalVault = SubVault({nft: tokenId, addr: _msgSender()});
        if (!_delegatedVaultIsOwned(vaultNft, externalVault)) {
            subVaultsIndex[vaultNft].push(externalVault);
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    function _allowTokenIfNecessary(address token, address vaults) internal {
        // !!! TODO: this is not secure, add whitelist here - WhiteListAllowance contract
        if (
            protocolGovernance.isAllowedToPull(token) &&
            IERC20(token).allowance(address(this), address(vaults)) < type(uint256).max / 2
        ) {
            IERC20(token).approve(address(vaults), type(uint256).max);
        }
    }
}
