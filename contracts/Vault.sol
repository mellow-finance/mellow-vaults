// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IGatewayVault.sol";
import "./libraries/Common.sol";
import "./interfaces/IVault.sol";
import "./VaultGovernance.sol";
import "hardhat/console.sol";

/// @notice Abstract contract that has logic common for every Vault.
abstract contract Vault is IVault {
    using SafeERC20 for IERC20;

    IVaultGovernance internal _vaultGovernance;
    address[] internal _vaultTokens;
    mapping(address => bool) internal _vaultTokensIndex;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance of this Vault
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_) {
        require(Common.isSortedAndUnique(vaultTokens_), "SAU");
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
    function earnings() public view virtual returns (uint256[] memory tokenAmounts);

    // -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED  -------------------

    /// @inheritdoc IVault
    function push(
        address[] memory tokens,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) public returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        uint256[] memory pActualTokenAmounts = _push(pTokenAmounts, options);
        actualTokenAmounts = Common.projectTokenAmounts(tokens, _vaultTokens, pActualTokenAmounts);
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
        address owner = registry.ownerOf(_selfNft());
        require(owner == msg.sender || _isValidPullDestination(to), "INTRA"); // approved can only pull to whitelisted contracts
        uint256[] memory pTokenAmounts = _validateAndProjectTokens(tokens, tokenAmounts);
        uint256[] memory pActualTokenAmounts = _pull(to, pTokenAmounts, options);
        actualTokenAmounts = Common.projectTokenAmounts(tokens, _vaultTokens, pActualTokenAmounts);
        emit Pull(to, actualTokenAmounts);
    }

    /// @inheritdoc IVault
    function collectEarnings(address to, bytes memory options) external returns (uint256[] memory collectedEarnings) {
        /// TODO: is allowed to pull
        /// TODO: verify that only RouterVault can call this (for fees reasons)
        require(_isApprovedOrOwner(msg.sender), "IO"); // Also checks that the token exists
        require(_isValidPullDestination(to), "INTRA");
        collectedEarnings = _collectEarnings(to, options);
        IProtocolGovernance governance = _vaultGovernance.internalParams().protocolGovernance;
        address protocolTres = governance.protocolTreasury();
        uint256 protocolPerformanceFee = governance.protocolPerformanceFee();
        uint256 strategyPerformanceFee = governance.strategyPerformanceFee();
        uint256 nft = _vaultGovernance.internalParams().registry.nftForVault(address(this));
        address strategyTres = _vaultGovernance.strategyTreasury(nft);
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            IERC20 token = IERC20(_vaultTokens[i]);
            uint256 protocolFee = (collectedEarnings[i] * protocolPerformanceFee) / Common.DENOMINATOR;
            uint256 strategyFee = (collectedEarnings[i] * strategyPerformanceFee) / Common.DENOMINATOR;
            uint256 strategyEarnings = collectedEarnings[i] - protocolFee - strategyFee;
            token.safeTransfer(strategyTres, strategyFee);
            token.safeTransfer(protocolTres, protocolFee);
            token.safeTransfer(to, strategyEarnings);
        }
        /// TODO: emit CollectedFees
        emit CollectEarnings(to, collectedEarnings);
    }

    // -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED OR PROTOCOL ADMIN -------------------
    /// @inheritdoc IVault
    function reclaimTokens(address to, address[] memory tokens) external {
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

    // -------------------  PRIVATE, VIEW  -------------------

    function _validateAndProjectTokens(address[] memory tokens, uint256[] memory tokenAmounts)
        internal
        view
        returns (uint256[] memory pTokenAmounts)
    {
        require(Common.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == tokenAmounts.length, "L");
        pTokenAmounts = Common.projectTokenAmounts(_vaultTokens, tokens, tokenAmounts);
    }

    /// The idea is to check that `this` Vault and `to` Vault
    /// nfts are owned by the same address. Then check that nft for this address
    /// exists in registry as Vault => it's one of the vaults with trusted interface.
    /// Then check that both `this` and `to` are registered in the nft owner using hasSubvault function.
    /// Since only gateway vault has hasSubvault function this will prove correctly that
    /// the vaults belong to the same vault system.
    function _isValidPullDestination(address to) internal view returns (bool) {
        if (!Common.isContract(to)) {
            return false;
        }
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256 thisNft = registry.nftForVault(address(this));
        address thisOwner = registry.ownerOf(thisNft);
        uint256 toNft = registry.nftForVault(to);
        address toOwner = registry.ownerOf(toNft);
        console.log("Vault::_isValidPullDestination thisNft", thisNft);
        console.log("Vault::_isValidPullDestination thisOwner", thisOwner);
        console.log("Vault::_isValidPullDestination toNft", toNft);
        console.log("Vault::_isValidPullDestination toOwner", toOwner);
        // make sure that vault is a registered vault
        uint256 thisOwnerNft = registry.nftForVault(thisOwner);
        uint256 toOwnerNft = registry.nftForVault(toOwner);
        console.log("Vault::_isValidPullDestination thisOwnerNft", thisOwnerNft);
        console.log("Vault::_isValidPullDestination toOwnerNft", toOwnerNft);
        if ((toOwnerNft == 0) || (thisOwnerNft != toOwnerNft) || (thisOwner != toOwner)) {
            return false;
        }
        IGatewayVault gw = IGatewayVault(thisOwner);
        console.log("_isValidPullDestination: gw.hasSubvault(to)", gw.hasSubvault(to));
        console.log("_isValidPullDestination: gw.hasSubvault(this)", gw.hasSubvault(address(this)));

        if (!gw.hasSubvault(address(this)) || !gw.hasSubvault(to)) {
            return false;
        }
        return true;
    }

    // -------------------  PRIVATE, VIEW  -------------------

    function _selfNft() internal view returns (uint256) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        return registry.nftForVault(address(this));
    }

    function _isApprovedOrOwner(address sender) internal view returns (bool) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256 nft = registry.nftForVault(address(this));
        console.log("Vault::_isApprovedOrOwner: nft", nft);
        if (nft == 0) {
            return false;
        }
        console.log("Vault::_isApprovedOrOwner: registry.getApproved(nft)", registry.getApproved(nft));
        console.log("Vault::_isApprovedOrOwner: registry.ownerOf(nft)", registry.ownerOf(nft));
        console.log("Vault::_isApprovedOrOwner: sender", sender);
        return registry.getApproved(nft) == sender || registry.ownerOf(nft) == sender;
    }

    function _isVaultToken(address token) internal view returns (bool) {
        return _vaultTokensIndex[token];
    }

    // -------------------  PRIVATE, MUTATING  -------------------

    /// Guaranteed to have exact signature matchinn vault tokens
    function _push(
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal virtual returns (uint256[] memory actualTokenAmounts);

    /// Guaranteed to have exact signature matchinn vault tokens
    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal virtual returns (uint256[] memory actualTokenAmounts);

    function _collectEarnings(address to, bytes memory options)
        internal
        virtual
        returns (uint256[] memory collectedEarnings);

    function _postReclaimTokens(address to, address[] memory tokens) internal virtual {}

    /// @notice Emitted on successful push
    /// @param tokenAmounts The amounts of tokens to pushed
    event Push(uint256[] tokenAmounts);

    /// @notice Emitted on successful pull
    /// @param to The target address for pulled tokens
    /// @param tokenAmounts The amounts of tokens to pull
    event Pull(address to, uint256[] tokenAmounts);

    /// @notice Emitted when earnings are collected
    /// @param to The target address for pulled tokens
    /// @param tokenAmounts The amounts of earnings
    event CollectEarnings(address to, uint256[] tokenAmounts);

    /// @notice Emitted when tokens are reclaimed
    /// @param to The target address for pulled tokens
    /// @param tokens ERC20 tokens to be reclaimed
    /// @param tokenAmounts The amounts of reclaims
    event ReclaimTokens(address to, address[] tokens, uint256[] tokenAmounts);
}
