// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./DefaultAccessControl.sol";
import "./VaultGovernanceOld.sol";
import "./libraries/Common.sol";

import "./interfaces/IVaultManager.sol";
import "./interfaces/IVault.sol";

abstract contract Vault is IVault {
    using SafeERC20 for IERC20;

    IVaultGovernanceOld internal _vaultGovernance;

    constructor(IVaultGovernanceOld vaultGovernance_) {
        _vaultGovernance = vaultGovernance_;
    }

    // -------------------  PUBLIC, VIEW  -------------------

    /// @inheritdoc IVault
    function vaultGovernance() external view returns (IVaultGovernanceOld) {
        return _vaultGovernance;
    }

    /// @inheritdoc IVault
    function tvl() public view virtual returns (uint256[] memory tokenAmounts);

    /// @inheritdoc IVault
    function earnings() public view virtual returns (uint256[] memory tokenAmounts);

    // -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED  -------------------

    /// @inheritdoc IVault
    function push(
        address[] memory tokens,
        uint256[] memory tokenAmounts,
        bool optimized,
        bytes memory options
    ) public returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        uint256[] memory pActualTokenAmounts = _push(pTokenAmounts, optimized, options);
        actualTokenAmounts = Common.projectTokenAmounts(tokens, _vaultGovernance.vaultTokens(), pActualTokenAmounts);
        emit Push(pActualTokenAmounts);
    }

    /// @inheritdoc IVault
    function transferAndPush(
        address from,
        address[] memory tokens,
        uint256[] memory tokenAmounts,
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

    /// @inheritdoc IVault
    function pull(
        address to,
        address[] memory tokens,
        uint256[] memory tokenAmounts,
        bool optimized,
        bytes memory options
    ) external returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        uint256 nft = _vaultGovernance.vaultManager().nftForVault(address(this));
        address owner = _vaultGovernance.vaultManager().ownerOf(nft);
        require(owner == msg.sender || _isValidPullDestination(to), "INTRA"); // approved can only pull to whitelisted contracts
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        uint256[] memory pActualTokenAmounts = _pull(to, pTokenAmounts, optimized, options);
        actualTokenAmounts = Common.projectTokenAmounts(tokens, _vaultGovernance.vaultTokens(), pActualTokenAmounts);
        emit Pull(to, actualTokenAmounts);
    }

    /// @inheritdoc IVault
    function collectEarnings(address to, bytes memory options) external returns (uint256[] memory collectedEarnings) {
        /// TODO: is allowed to pull
        /// TODO: verify that only RouterVault can call this (for fees reasons)
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        require(_isValidPullDestination(to), "INTRA");
        collectedEarnings = _collectEarnings(to, options);
        IProtocolGovernance governance = _vaultGovernance.vaultManager().governanceParams().protocolGovernance;
        address protocolTres = governance.protocolTreasury();
        uint256 protocolPerformanceFee = governance.protocolPerformanceFee();
        uint256 strategyPerformanceFee = governance.strategyPerformanceFee();
        address strategyTres = _vaultGovernance.strategyTreasury();
        address[] memory _vaultTokens = _vaultGovernance.vaultTokens();
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

    // -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED OR PROTOCOL ADMIN -------------------
    /// @inheritdoc IVault
    function reclaimTokens(address to, address[] memory tokens) external {
        bool isProtocolAdmin = _vaultGovernance.isProtocolAdmin(msg.sender);
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
        emit IVault.ReclaimTokens(to, tokens, tokenAmounts);
    }

    // TODO: Add to governance specific bytes for each contract that shows withdraw address
    /// @inheritdoc IVault
    function claimRewards(address from, bytes memory data) external override {
        require(_isApprovedOrOwner(msg.sender), "ADM");
        IProtocolGovernance protocolGovernance = _vaultGovernance.vaultManager().governanceParams().protocolGovernance;
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

    // -------------------  PRIVATE, VIEW  -------------------

    function _validateAndProjectTokens(address[] memory tokens, uint256[] memory tokenAmounts)
        internal
        view
        returns (uint256[] memory pTokenAmounts)
    {
        require(Common.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == tokenAmounts.length, "L");
        pTokenAmounts = Common.projectTokenAmounts(_vaultGovernance.vaultTokens(), tokens, tokenAmounts);
    }

    function _isValidPullDestination(address to) internal view returns (bool) {
        require(Common.isContract(to), "C");
        IVaultManager vaultManager = _vaultGovernance.vaultManager();
        IGatewayVaultManager gw = vaultManager.governanceParams().protocolGovernance.gatewayVaultManager();
        uint256 fromNft = vaultManager.nftForVault(address(this));
        uint256 toNft = IVault(to).vaultGovernance().vaultManager().nftForVault(to);
        uint256 voFromNft = gw.vaultOwnerNft(fromNft);
        if (voFromNft == 0) {
            return false;
        }
        return voFromNft == gw.vaultOwnerNft(toNft);
    }

    // -------------------  PRIVATE, VIEW  -------------------

    function _isApprovedOrOwner(address sender) internal view returns (bool) {
        IVaultManager vaultManager = _vaultGovernance.vaultManager();
        uint256 nft = vaultManager.nftForVault(address(this));
        if (nft == 0) {
            return false;
        }
        return vaultManager.getApproved(nft) == sender || vaultManager.ownerOf(nft) == sender;
    }

    // -------------------  PRIVATE, MUTATING  -------------------

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
