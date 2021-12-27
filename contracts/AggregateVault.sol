// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IGatewayVault.sol";
import "./interfaces/IGatewayVaultGovernance.sol";
import "./Vault.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice Vault that combines several integration layer Vaults into one Vault.
contract AggregateVault is Vault {
    uint256[] private _subvaultNfts;
    mapping(uint256 => uint256) private _subvaultNftsIndex;

    constructor(
        IVaultGovernance vaultGovernance_,
        address[] memory vaultTokens_,
        uint256 nft_,
        uint256[] memory subvaultNfts_
    ) Vault(vaultGovernance_, vaultTokens_, nft_) {
        IVaultRegistry vaultRegistry = vaultGovernance_.internalParams().registry;
        for (uint256 i = 0; i < subvaultNfts_.length; i++) {
            uint256 nft = subvaultNfts_[i];
            require(nft > 0, ExceptionsLibrary.NFT_ZERO);
            require(vaultRegistry.ownerOf(nft) == address(this), ExceptionsLibrary.TOKEN_OWNER);
            require(vaultRegistry.isLocked(nft), ExceptionsLibrary.LOCKED_NFT);
            require(_subvaultNftsIndex[nft] == 0, ExceptionsLibrary.DUPLICATE_NFT);
            address vault = vaultRegistry.vaultForNft(nft);
            require(vault != address(0), ExceptionsLibrary.VAULT_ADDRESS_ZERO);
            require(IVault(vault).supportsInterface(type(IVault).interfaceId), ExceptionsLibrary.NOT_VAULT);
            _subvaultNftsIndex[nft] = i + 1;
        }
        _subvaultNfts = subvaultNfts_;
    }

    function subvaultNfts() external view returns (uint256[] memory) {
        return _subvaultNfts;
    }

    function subvaultOneBasedIndex(uint256 nft) external view returns (uint256) {
        return _subvaultNftsIndex[nft];
    }

    /// @inheritdoc IGatewayVault
    function hasSubvault(address vault) external view override returns (bool) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256 nft = registry.nftForVault(vault);
        return (_subvaultNftsIndex[nft] > 0);
    }


    /// @inheritdoc IVault
    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        minTokenAmounts = new uint256[](_vaultTokens.length);
        maxTokenAmounts = new uint256[](_vaultTokens.length);
        for (uint256 i = 0; i < _subvaultNfts.length; ++i) {
            IVault vault = IVault(registry.vaultForNft(_subvaultNfts[i]));
            (uint256[] memory sMinTokenAmounts, uint256[] memory sMaxTokenAmounts) = vault.tvl();
            for (uint256 j = 0; j < _vaultTokens.length; ++j) {
                minTokenAmounts[j] += sMinTokenAmounts[j];
                maxTokenAmounts[j] += sMaxTokenAmounts[j];
            }
        }
    }

    function setApprovalsForStrategy(address strategy) external {
        require(msg.sender == address(_vaultGovernance), ExceptionsLibrary.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE);
        require(strategy != address(0), ExceptionsLibrary.ZERO_STRATEGY_ADDRESS);
        IVaultRegistry vaultRegistry = IVaultGovernance(_vaultGovernance).internalParams().registry;
        uint256[] memory nfts = _subvaultNfts;
        uint256 len = nfts.length;
        for (uint256 i = 0; i < len; ++i) {
            vaultRegistry.approve(strategy, nfts[i]);
        }
    }

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        address from = msg.sender;
        if (options.length > 0) {
            from = abi.decode(options, (address));
        }
        uint256 destNft = _subvaultNfts[0];
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        IVault destVault = IVault(registry.vaultForNft(destNft));
        actualTokenAmounts = destVault.transferAndPush(msg.sender, _vaultTokens, tokenAmounts, "");
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
    }

    function _allowTokenIfNecessary(address token, address to) internal {
        if (IERC20(token).allowance(address(this), address(to)) < type(uint256).max / 2) {
            IERC20(token).approve(address(to), type(uint256).max);
        }
    }

    function _parseOptions(bytes memory options) internal view returns (bool, bytes[] memory) {
        if (options.length == 0) {
            return (false, new bytes[](_subvaultNfts.length));
        }
        return abi.decode(options, (bool, bytes[]));
    }

    event CollectProtocolFees(address protocolTreasury, address[] tokens, uint256[] amounts);
    event CollectStrategyFees(address strategyTreasury, address[] tokens, uint256[] amounts);
}
