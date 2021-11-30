// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IGatewayVault.sol";
import "./libraries/CommonLibrary.sol";
import "./interfaces/IVault.sol";
import "./VaultGovernance.sol";

/// @notice Abstract contract that has logic common for every Vault.
abstract contract Vault is IVault {
    using SafeERC20 for IERC20;

    IVaultGovernance internal _vaultGovernance;
    address[] internal _vaultTokens;
    mapping(address => bool) internal _vaultTokensIndex;
    uint256 internal _nft;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance of this Vault
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_) {
        require(CommonLibrary.isSortedAndUnique(vaultTokens_), "SAU");
        _vaultGovernance = vaultGovernance_;
        _vaultTokens = vaultTokens_;
        for (uint256 i = 0; i < vaultTokens_.length; i++) {
            _vaultTokensIndex[vaultTokens_[i]] = true;
        }
    }

    // -------------------  PUBLIC, VIEW  -------------------

    /// @inheritdoc IVault
    function vaultGovernance() external view returns (IVaultGovernance) {
        return _vaultGovernance;
    }

    /// @inheritdoc IVault
    function vaultTokens() external view returns (address[] memory) {
        return _vaultTokens;
    }

    /// @inheritdoc IVault
    function tvl() public view virtual returns (uint256[] memory tokenAmounts);

    /// @inheritdoc IVault
    function nft() external view returns (uint256) {
        return _nft;
    }

    // -------------------  PUBLIC, MUTATING, VaultGovernance  -------------------

    function initialize(uint256 nft_) external {
        require(msg.sender == address(_vaultGovernance), "VG");
        _nft = nft_;
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        registry.setApprovalForAll(address(registry), true);
    }

    // -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED  -------------------

    /// @inheritdoc IVault
    function push(
        address[] memory tokens,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) public returns (uint256[] memory actualTokenAmounts) {
        require(_nft > 0, "INIT");
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        uint256[] memory pActualTokenAmounts = _push(pTokenAmounts, options);
        actualTokenAmounts = CommonLibrary.projectTokenAmounts(tokens, _vaultTokens, pActualTokenAmounts);
        emit Push(pActualTokenAmounts);
    }

    /// @inheritdoc IVault
    function transferAndPush(
        address from,
        address[] memory tokens,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenAmounts[i] > 0) {
                IERC20(tokens[i]).safeTransferFrom(from, address(this), tokenAmounts[i]);
            }
        }
        actualTokenAmounts = push(tokens, tokenAmounts, options);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 leftover = actualTokenAmounts[i] < tokenAmounts[i] ? tokenAmounts[i] - actualTokenAmounts[i] : 0;
            if (leftover > 0) {
                IERC20(tokens[i]).safeTransfer(from, leftover);
            }
        }
    }

    /// @inheritdoc IVault
    function pull(
        address to,
        address[] memory tokens,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(_nft);
        require(owner == msg.sender || _isValidPullDestination(to), "INTRA"); // approved can only pull to whitelisted contracts
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        uint256[] memory pActualTokenAmounts = _pull(to, pTokenAmounts, options);
        actualTokenAmounts = CommonLibrary.projectTokenAmounts(tokens, _vaultTokens, pActualTokenAmounts);
        emit Pull(to, actualTokenAmounts);
    }

    // -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED OR PROTOCOL ADMIN -------------------
    /// @inheritdoc IVault
    function reclaimTokens(address to, address[] memory tokens) external {
        require(_nft > 0, "INIT");
        IProtocolGovernance governance = _vaultGovernance.internalParams().protocolGovernance;
        bool isProtocolAdmin = governance.isAdmin(msg.sender);
        require(isProtocolAdmin || _isApprovedOrOwner(msg.sender), "ADM");
        if (!isProtocolAdmin) {
            require(_isValidPullDestination(to), "INTRA");
        }
        uint256[] memory tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            tokenAmounts[i] = token.balanceOf(address(this));
            if (tokenAmounts[i] == 0) {
                continue;
            }
            token.safeTransfer(to, tokenAmounts[i]);
        }
        _postReclaimTokens(to, tokens);
        emit ReclaimTokens(to, tokens, tokenAmounts);
    }

    // TODO: Add to governance specific bytes for each contract that shows withdraw address
    /// @inheritdoc IVault
    function claimRewards(address from, bytes memory data) external override {
        require(_nft > 0, "INIT");
        require(_isApprovedOrOwner(msg.sender), "ADM");
        IProtocolGovernance protocolGovernance = _vaultGovernance.internalParams().protocolGovernance;
        require(protocolGovernance.isAllowedToClaim(from), "AC");
        (bool res, bytes memory returndata) = from.call(data);
        if (!res) {
            assembly {
                let returndata_size := mload(returndata)
                // Bubble up revert reason
                revert(add(32, returndata), returndata_size)
            }
        }
    }

    // -------------------  PUBLIC, VIEW   -------------------\

    function isVaultToken(address token) public view returns (bool) {
        return _vaultTokensIndex[token];
    }

    // -------------------  PRIVATE, VIEW  -------------------

    function _validateAndProjectTokens(address[] memory tokens, uint256[] memory tokenAmounts)
        internal
        view
        returns (uint256[] memory pTokenAmounts)
    {
        require(CommonLibrary.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == tokenAmounts.length, "L");
        pTokenAmounts = CommonLibrary.projectTokenAmounts(_vaultTokens, tokens, tokenAmounts);
    }

    /// The idea is to check that `this` Vault and `to` Vault
    /// nfts are owned by the same address. Then check that nft for this address
    /// exists in registry as Vault => it's one of the vaults with trusted interface.
    /// Then check that both `this` and `to` are registered in the nft owner using hasSubvault function.
    /// Since only gateway vault has hasSubvault function this will prove correctly that
    /// the vaults belong to the same vault system.
    function _isValidPullDestination(address to) internal view returns (bool) {
        if (!CommonLibrary.isContract(to)) {
            return false;
        }
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        // make sure that this vault is a registered vault
        if (_nft == 0) {
            return false;
        }
        address thisOwner = registry.ownerOf(_nft);
        // make sure that vault has a registered owner
        uint256 thisOwnerNft = registry.nftForVault(thisOwner);
        if (thisOwnerNft == 0) {
            return false;
        }
        IGatewayVault gw = IGatewayVault(thisOwner);
        if (!gw.hasSubvault(address(this)) || !gw.hasSubvault(to)) {
            return false;
        }
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
