// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/vaults/IVaultRoot.sol";
import "../interfaces/vaults/IIntegrationVault.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/AddressPermissionIds.sol";
import "./VaultGovernance.sol";
import "./Vault.sol";

/// @notice Abstract contract that has logic common for every Vault.
/// @dev Notes:
/// ### ERC-721
///
/// Each Vault should be registered in VaultRegistry and get corresponding VaultRegistry NFT.
///
/// ### Access control
///
/// `push` and `pull` methods are only allowed for owner / approved person of the NFT. However,
/// `pull` for approved person also checks that pull destination is another vault of the Vault System.
///
/// The semantics is: NFT owner owns all Vault liquidity, Approved person is liquidity manager.
/// ApprovedForAll person cannot do anything except ERC-721 token transfers.
///
/// Both NFT owner and approved person can call claimRewards method which claims liquidity mining rewards (if any)
///
/// `reclaimTokens` for mistakenly transfered tokens (not included into vaultTokens) additionally can be withdrawn by
/// the protocol admin
abstract contract IntegrationVault is IIntegrationVault, ReentrancyGuard, Vault {
    using SafeERC20 for IERC20;

    // -------------------  EXTERNAL, MUTATING, NFT OWNER OR APPROVED  -------------------

    /// @inheritdoc IIntegrationVault
    function push(
        address[] memory tokens,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) public nonReentrant returns (uint256[] memory actualTokenAmounts) {
        uint256 nft_ = _nft;
        require(nft_ != 0, ExceptionsLibrary.INIT);
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN); // Also checks that the token exists
        IVaultRegistry vaultRegistry = _vaultGovernance.internalParams().registry;
        IVault ownerVault = IVault(vaultRegistry.ownerOf(nft_));
        uint256 ownerNft = vaultRegistry.nftForVault(address(ownerVault));
        require(ownerNft != 0, ExceptionsLibrary.NOT_FOUND); // require deposits only through Vault
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        uint256[] memory pActualTokenAmounts = _push(pTokenAmounts, options);
        actualTokenAmounts = CommonLibrary.projectTokenAmounts(tokens, _vaultTokens, pActualTokenAmounts);
        emit Push(pActualTokenAmounts);
    }

    /// @inheritdoc IIntegrationVault
    function transferAndPush(
        address from,
        address[] memory tokens,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts) {
        uint256 len = tokens.length;
        for (uint256 i = 0; i < len; ++i)
            if (tokenAmounts[i] != 0) IERC20(tokens[i]).safeTransferFrom(from, address(this), tokenAmounts[i]);

        actualTokenAmounts = push(tokens, tokenAmounts, options);
        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 leftover = actualTokenAmounts[i] < tokenAmounts[i] ? tokenAmounts[i] - actualTokenAmounts[i] : 0;
            if (leftover != 0) IERC20(tokens[i]).safeTransfer(from, leftover);
        }
    }

    /// @inheritdoc IIntegrationVault
    function pull(
        address to,
        address[] memory tokens,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) external nonReentrant returns (uint256[] memory actualTokenAmounts) {
        uint256 nft_ = _nft;
        require(nft_ != 0, ExceptionsLibrary.INIT);
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(nft_);
        require(owner == msg.sender || _isValidPullDestination(to), ExceptionsLibrary.INVALID_TARGET); // approved can only pull to whitelisted contracts
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        uint256[] memory pActualTokenAmounts = _pull(to, pTokenAmounts, options);
        actualTokenAmounts = CommonLibrary.projectTokenAmounts(tokens, _vaultTokens, pActualTokenAmounts);
        emit Pull(to, actualTokenAmounts);
    }

    // -------------------  EXTERNAL, MUTATING, NFT OWNER OR APPROVED OR PROTOCOL FORBIDDEN -------------------

    /// @inheritdoc IIntegrationVault
    function reclaimTokens(address to, address[] memory tokens) external nonReentrant {
        require(_nft != 0, ExceptionsLibrary.INIT);
        IProtocolGovernance governance = _vaultGovernance.internalParams().protocolGovernance;
        bool isProtocolAdmin = governance.isAdmin(msg.sender);
        require(isProtocolAdmin || _isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        if (!isProtocolAdmin) require(_isValidPullDestination(to), ExceptionsLibrary.INVALID_TARGET);

        uint256[] memory tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            require(
                governance.hasPermission(tokens[i], AddressPermissionIds.ERC20_TRANSFER),
                ExceptionsLibrary.INVALID_TOKEN
            );
            IERC20 token = IERC20(tokens[i]);
            tokenAmounts[i] = token.balanceOf(address(this));
            if (tokenAmounts[i] == 0) continue;

            token.safeTransfer(to, tokenAmounts[i]);
        }
        _postReclaimTokens(to, tokens);
        emit ReclaimTokens(to, tokens, tokenAmounts);
    }

    /// @inheritdoc IIntegrationVault
    function claimRewards(address from, bytes memory data) external override nonReentrant {
        require(_nft != 0, ExceptionsLibrary.INIT);
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        IProtocolGovernance protocolGovernance = _vaultGovernance.internalParams().protocolGovernance;
        require(protocolGovernance.hasPermission(from, AddressPermissionIds.CLAIM), ExceptionsLibrary.FORBIDDEN);
        (bool res, bytes memory returndata) = from.call(data);
        if (!res) {
            assembly {
                let returndata_size := mload(returndata)
                // Bubble up revert reason
                revert(add(32, returndata), returndata_size)
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, Vault) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IIntegrationVault).interfaceId);
    }

    // -------------------  PRIVATE, VIEW  -------------------

    function _validateAndProjectTokens(address[] memory tokens, uint256[] memory tokenAmounts)
        internal
        view
        returns (uint256[] memory pTokenAmounts)
    {
        require(CommonLibrary.isSortedAndUnique(tokens), ExceptionsLibrary.INVARIANT);
        require(tokens.length == tokenAmounts.length, ExceptionsLibrary.INVALID_VALUE);
        pTokenAmounts = CommonLibrary.projectTokenAmounts(_vaultTokens, tokens, tokenAmounts);
    }

    /// The idea is to check that `this` Vault and `to` Vault
    /// nfts are owned by the same address. Then check that nft for this address
    /// exists in registry as Vault => it's one of the vaults with trusted interface.
    /// Then check that both `this` and `to` are registered in the nft owner using hasSubvault function.
    /// Since only gateway vault has hasSubvault function this will prove correctly that
    /// the vaults belong to the same vault system.
    function _isValidPullDestination(address to) internal view returns (bool) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        // make sure that this vault is a registered vault
        if (_nft == 0) return false;

        address thisOwner = registry.ownerOf(_nft);
        // make sure that vault has a registered owner
        uint256 thisOwnerNft = registry.nftForVault(thisOwner);
        if (thisOwnerNft == 0) return false;

        IVaultRoot root = IVaultRoot(thisOwner);
        if (!root.hasSubvault(address(this)) || !root.hasSubvault(to)) return false;

        return true;
    }

    // -------------------  PRIVATE, VIEW  -------------------

    function _isApprovedOrOwner(address sender) internal view returns (bool) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256 nft_ = _nft;
        if (nft_ == 0) {
            return false;
        }
        return registry.getApproved(nft_) == sender || registry.ownerOf(nft_) == sender;
    }

    // -------------------  PRIVATE, MUTATING  -------------------

    /// Guaranteed to have exact signature matchinn vault tokens
    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        virtual
        returns (uint256[] memory actualTokenAmounts);

    /// Guaranteed to have exact signature matchinn vault tokens
    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal virtual returns (uint256[] memory actualTokenAmounts);

    function _postReclaimTokens(address to, address[] memory tokens) internal virtual {}

    /// @notice Emitted on successful push
    /// @param tokenAmounts The amounts of tokens to pushed
    event Push(uint256[] tokenAmounts);

    /// @notice Emitted on successful pull
    /// @param to The target address for pulled tokens
    /// @param tokenAmounts The amounts of tokens to pull
    event Pull(address to, uint256[] tokenAmounts);

    /// @notice Emitted when tokens are reclaimed
    /// @param to The target address for pulled tokens
    /// @param tokens ERC20 tokens to be reclaimed
    /// @param tokenAmounts The amounts of reclaims
    event ReclaimTokens(address to, address[] tokens, uint256[] tokenAmounts);
}
