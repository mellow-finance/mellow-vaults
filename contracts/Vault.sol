// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./DefaultAccessControl.sol";
import "./VaultGovernance.sol";
import "./libraries/Common.sol";

import "./interfaces/IVaultManager.sol";
import "./interfaces/IVault.sol";

abstract contract Vault is IVault, VaultGovernance {
    using SafeERC20 for IERC20;

    address[] private _vaultTokens;
    mapping(address => bool) private _vaultTokensIndex;

    constructor(
        address[] memory tokens,
        IVaultManager vaultManager_,
        address strategyTreasury,
        address admin
    ) VaultGovernance(vaultManager_, strategyTreasury, admin) {
        require(Common.isSortedAndUnique(tokens), "SAU");
        require(tokens.length > 0, "TL");
        require(tokens.length <= vaultManager_.governanceParams().protocolGovernance.maxTokensPerVault(), "MTL");
        _vaultTokens = tokens;
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

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IVault).interfaceId || super.supportsInterface(interfaceId);
    }

    function tvl() public view virtual returns (uint256[] memory tokenAmounts);

    function earnings() public view virtual returns (uint256[] memory tokenAmounts);

    /// -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED  -------------------

    /// tokens are used from contract balance
    function push(
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        bool optimized,
        bytes memory options
    ) public returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        uint256[] memory pActualTokenAmounts = _push(pTokenAmounts, optimized, options);
        actualTokenAmounts = Common.projectTokenAmounts(tokens, _vaultTokens, pActualTokenAmounts);
        emit Push(pActualTokenAmounts);
    }

    function transferAndPush(
        address from,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        bool optimized,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenAmounts[i] > 0) {
                IERC20(tokens[i]).safeTransferFrom(from, address(this), tokenAmounts[i]);
            }
        }
        actualTokenAmounts = push(tokens, tokenAmounts, optimized, options);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 leftover = actualTokenAmounts[i] < tokenAmounts[i] ? tokenAmounts[i] - actualTokenAmounts[i] : 0;
            if (leftover > 0) {
                IERC20(tokens[i]).safeTransfer(from, leftover);
            }
        }
    }

    function pull(
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts,
        bool optimized,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        uint256 nft = vaultManager().nftForVault(address(this));
        address owner = vaultManager().ownerOf(nft);
        require(owner == msg.sender || _isValidPullDestination(to), "INTRA"); // approved can only pull to whitelisted contracts
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        uint256[] memory pActualTokenAmounts = _pull(to, pTokenAmounts, optimized, options);
        actualTokenAmounts = Common.projectTokenAmounts(tokens, _vaultTokens, pActualTokenAmounts);
        emit Pull(to, actualTokenAmounts);
    }

    function collectEarnings(address to, bytes memory options) external returns (uint256[] memory collectedEarnings) {
        /// TODO: is allowed to pull
        /// TODO: verify that only RouterVault can call this (for fees reasons)
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        require(_isValidPullDestination(to), "INTRA");
        collectedEarnings = _collectEarnings(to, options);
        IProtocolGovernance governance = vaultManager().governanceParams().protocolGovernance;
        address protocolTres = governance.protocolTreasury();
        uint256 protocolPerformanceFee = governance.protocolPerformanceFee();
        uint256 strategyPerformanceFee = governance.strategyPerformanceFee();
        address strategyTres = strategyTreasury();
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            IERC20 token = IERC20(_vaultTokens[i]);
            uint256 protocolFee = (collectedEarnings[i] * protocolPerformanceFee) / Common.DENOMINATOR;
            uint256 strategyFee = (collectedEarnings[i] * strategyPerformanceFee) / Common.DENOMINATOR;
            uint256 strategyEarnings = collectedEarnings[i] - protocolFee - strategyFee;
            token.safeTransfer(strategyTres, strategyFee);
            token.safeTransfer(protocolTres, protocolFee);
            token.safeTransfer(to, strategyEarnings);
        }
        emit IVault.CollectEarnings(to, collectedEarnings);
    }

    /// -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED OR PROTOCOL ADMIN -------------------
    function reclaimTokens(address to, address[] calldata tokens) external {
        require(_isProtocolAdmin() || _isApprovedOrOwner(msg.sender), "ADM");
        if (!_isProtocolAdmin()) {
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
        emit IVault.ReclaimTokens(to, tokens, tokenAmounts);
    }

    // TODO: Add to governance specific bytes for each contract that shows withdraw address
    function claimRewards(address from, bytes calldata data) external {
        require(isAdmin() || _isApprovedOrOwner(msg.sender), "ADM");
        IProtocolGovernance protocolGovernance = vaultManager().governanceParams().protocolGovernance;
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

    function _isValidPullDestination(address to) internal view returns (bool) {
        IGatewayVaultManager gw = vaultManager().governanceParams().protocolGovernance.gatewayVaultManager();
        uint256 fromNft = vaultManager().nftForVault(address(this));
        uint256 toNft = IVault(to).vaultManager().nftForVault(to);
        uint256 voFromNft = gw.vaultOwnerNft(fromNft);
        if (voFromNft == 0) {
            return false;
        }
        return voFromNft == gw.vaultOwnerNft(toNft);
    }

    /// -------------------  PRIVATE, VIEW  -------------------

    function _isApprovedOrOwner(address sender) internal view returns (bool) {
        uint256 nft = vaultManager().nftForVault(address(this));
        if (nft == 0) {
            return false;
        }
        return vaultManager().getApproved(nft) == sender || vaultManager().ownerOf(nft) == sender;
    }

    /// -------------------  PRIVATE, MUTATING  -------------------

    /// Guaranteed to have exact signature matchinn vault tokens
    function _push(
        uint256[] memory tokenAmounts,
        bool optimized,
        bytes memory options
    ) internal virtual returns (uint256[] memory actualTokenAmounts);

    /// Guaranteed to have exact signature matchinn vault tokens
    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bool optimized,
        bytes memory options
    ) internal virtual returns (uint256[] memory actualTokenAmounts);

    function _collectEarnings(address to, bytes memory options)
        internal
        virtual
        returns (uint256[] memory collectedEarnings);

    function _postReclaimTokens(address to, address[] memory tokens) internal virtual {}
}
