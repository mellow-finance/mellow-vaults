// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./GovernanceAccessControl.sol";
import "./VaultGovernance.sol";
import "./libraries/Common.sol";

import "./interfaces/IVaultManager.sol";
import "./interfaces/IVault.sol";

abstract contract Vault is IVault, VaultGovernance {
    using SafeERC20 for IERC20;

    address[] private _vaultTokens;
    uint256[] private _vaultLimits;
    mapping(address => bool) private _vaultTokensIndex;

    constructor(
        address[] memory tokens,
        uint256[] memory limits,
        IVaultManager vaultManager
    ) VaultGovernance(vaultManager) {
        require(Common.isSortedAndUnique(tokens), "SAU");
        require(tokens.length > 0, "TL");
        require(tokens.length == limits.length, "LL");
        _vaultTokens = tokens;
        _vaultLimits = limits;
        for (uint256 i = 0; i < tokens.length; i++) {
            _vaultTokensIndex[tokens[i]] = true;
        }
    }

    /// -------------------  PUBLIC, VIEW  -------------------

    function vaultTokens() public view returns (address[] memory) {
        return _vaultTokens;
    }

    function isVaultToken(address token) public view returns (bool) {
        return _vaultTokensIndex[token];
    }

    function vaultLimits() public view returns (uint256[] memory) {
        return _vaultLimits;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IVault).interfaceId || super.supportsInterface(interfaceId);
    }

    function tvl() public view virtual returns (address[] memory tokens, uint256[] memory tokenAmounts);

    /// -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED  -------------------

    /// tokens are used from contract balance
    function push(address[] calldata tokens, uint256[] calldata tokenAmounts)
        public
        returns (uint256[] memory actualTokenAmounts)
    {
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        (, uint256[] memory tvls) = tvl();
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            require(pTokenAmounts[i] + tvls[i] < _vaultLimits[i], "OOB");
        }
        uint256[] memory pActualTokenAmounts = _push(pTokenAmounts);
        actualTokenAmounts = Common.projectTokenAmounts(tokens, _vaultTokens, pActualTokenAmounts);
        emit Push(pActualTokenAmounts);
    }

    function transferAndPush(
        address from,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external returns (uint256[] memory actualTokenAmounts) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenAmounts[i] > 0) {
                IERC20(tokens[i]).safeTransferFrom(from, address(this), tokenAmounts[i]);
            }
        }
        actualTokenAmounts = push(tokens, tokenAmounts);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 leftover = actualTokenAmounts[i] < tokenAmounts[i] ? tokenAmounts[i] - actualTokenAmounts[i] : 0;
            if (leftover > 0) {
                IERC20(tokens[i]).safeTransfer(from, leftover);
            }
        }
    }

    function pull(
        uint256 nft,
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        address owner = vaultManager().ownerOf(nft);
        require(owner == msg.sender || vaultManager().protocolGovernance().isAllowedToPull(to), "INTRA"); // approved can only pull to whitelisted contracts
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        uint256[] memory pActualTokenAmounts = _pull(to, pTokenAmounts);
        actualTokenAmounts = Common.projectTokenAmounts(tokens, _vaultTokens, pActualTokenAmounts);
        emit Pull(to, actualTokenAmounts);
    }

    function collectEarnings(address to, address[] calldata tokens)
        external
        returns (uint256[] memory collectedEarnings)
    {
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        require(vaultManager().protocolGovernance().isAllowedToPull(to), "INTRA");
        collectedEarnings = _collectEarnings(to, tokens);
        emit IVault.CollectEarnings(to, tokens, collectedEarnings);
    }

    /// -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED  -------------------
    function reclaimTokens(address to, address[] calldata tokens) external {
        require(_isGovernanceOrDelegate() || _isApprovedOrOwner(msg.sender), "GD");
        if (!_isGovernanceOrDelegate()) {
            require(vaultManager().protocolGovernance().isAllowedToPull(to), "INTRA");
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
        emit IVault.ReclaimTokens(to, tokens, tokenAmounts);
    }

    /// -------------------  PRIVATE, VIEW  -------------------

    function _validateAndProjectTokens(address[] calldata tokens, uint256[] calldata tokenAmounts)
        internal
        view
        returns (uint256[] memory pTokenAmounts)
    {
        require(Common.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == tokenAmounts.length, "L");
        pTokenAmounts = Common.projectTokenAmounts(_vaultTokens, tokens, tokenAmounts);
    }

    /// -------------------  PRIVATE, MUTATING  -------------------

    /// Guaranteed to have exact signature matchinn vault tokens
    function _push(uint256[] memory tokenAmounts) internal virtual returns (uint256[] memory actualTokenAmounts);

    /// Guaranteed to have exact signature matchinn vault tokens
    function _pull(address to, uint256[] memory tokenAmounts)
        internal
        virtual
        returns (uint256[] memory actualTokenAmounts);

    function _collectEarnings(address to, address[] memory tokens)
        internal
        virtual
        returns (uint256[] memory collectedEarnings);

    function _postReclaimTokens(address to, address[] memory tokens) internal virtual {}

    function _isApprovedOrOwner(address sender) internal view returns (bool) {
        uint256 nft = vaultManager().nftForVault(address(this));
        if (nft == 0) {
            return false;
        }
        return vaultManager().getApproved(nft) == sender || vaultManager().ownerOf(nft) == sender;
    }
}
