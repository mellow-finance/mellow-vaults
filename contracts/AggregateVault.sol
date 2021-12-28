// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./interfaces/IIntegrationVault.sol";
import "./interfaces/IVaultRoot.sol";
import "./Vault.sol";
import "./libraries/ExceptionsLibrary.sol";

/// @notice Vault that combines several integration layer Vaults into one Vault.
contract AggregateVault is IVaultRoot, Vault {
    using SafeERC20 for IERC20;
    uint256[] private _subvaultNfts;
    uint256[] private _pullExistentials;
    mapping(uint256 => uint256) private _subvaultNftsIndex;

    constructor(
        IVaultGovernance vaultGovernance_,
        address[] memory vaultTokens_,
        uint256 nft_,
        uint256[] memory subvaultNfts_
    ) Vault(vaultGovernance_, vaultTokens_, nft_) {
        IVaultRegistry vaultRegistry = vaultGovernance_.internalParams().registry;
        require(subvaultNfts_.length > 0, ExceptionsLibrary.ZERO_LENGTH);
        for (uint256 i = 0; i < subvaultNfts_.length; i++) {
            uint256 subvaultNft = subvaultNfts_[i];
            require(subvaultNft > 0, ExceptionsLibrary.NFT_ZERO);
            require(vaultRegistry.ownerOf(subvaultNft) == address(this), ExceptionsLibrary.TOKEN_OWNER);
            require(_subvaultNftsIndex[subvaultNft] == 0, ExceptionsLibrary.DUPLICATE_NFT);
            address vault = vaultRegistry.vaultForNft(subvaultNft);
            require(vault != address(0), ExceptionsLibrary.VAULT_ADDRESS_ZERO);
            require(
                IIntegrationVault(vault).supportsInterface(type(IIntegrationVault).interfaceId),
                ExceptionsLibrary.NOT_VAULT
            );
            vaultRegistry.lockNft(subvaultNft);
            _subvaultNftsIndex[subvaultNft] = i + 1;
        }
        for (uint256 i = 0; i < vaultTokens_.length; i++) {
            ERC20 token = ERC20(vaultTokens_[i]);
            _pullExistentials[i] = 10**(token.decimals() / 2);
        }
        _subvaultNfts = subvaultNfts_;
    }

    function subvaultNfts() external view returns (uint256[] memory) {
        return _subvaultNfts;
    }

    function subvaultOneBasedIndex(uint256 nft_) external view returns (uint256) {
        return _subvaultNftsIndex[nft_];
    }

    function hasSubvault(address vault) external view returns (bool) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        uint256 subvaultNft = registry.nftForVault(vault);
        return (_subvaultNftsIndex[subvaultNft] > 0);
    }

    /// @inheritdoc IVault
    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        minTokenAmounts = new uint256[](_vaultTokens.length);
        maxTokenAmounts = new uint256[](_vaultTokens.length);
        for (uint256 i = 0; i < _subvaultNfts.length; ++i) {
            IIntegrationVault vault = IIntegrationVault(registry.vaultForNft(_subvaultNfts[i]));
            (uint256[] memory sMinTokenAmounts, uint256[] memory sMaxTokenAmounts) = vault.tvl();
            for (uint256 j = 0; j < _vaultTokens.length; ++j) {
                minTokenAmounts[j] += sMinTokenAmounts[j];
                maxTokenAmounts[j] += sMaxTokenAmounts[j];
            }
        }
    }

    function approveAllSubvaults(address strategy) external {
        require(msg.sender == address(_vaultGovernance), ExceptionsLibrary.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE);
        require(strategy != address(0), ExceptionsLibrary.ZERO_STRATEGY_ADDRESS);
        IVaultRegistry vaultRegistry = IVaultGovernance(_vaultGovernance).internalParams().registry;
        uint256[] memory nfts = _subvaultNfts;
        uint256 len = nfts.length;
        for (uint256 i = 0; i < len; ++i) {
            vaultRegistry.approve(strategy, nfts[i]);
        }
    }

    function _push(uint256[] memory tokenAmounts, bytes memory) internal returns (uint256[] memory actualTokenAmounts) {
        uint256 destNft = _subvaultNfts[0];
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        IIntegrationVault destVault = IIntegrationVault(registry.vaultForNft(destNft));
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            _allowTokenIfNecessary(_vaultTokens[i], address(destVault));
        }
        actualTokenAmounts = destVault.transferAndPush(msg.sender, _vaultTokens, tokenAmounts, "");
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal returns (uint256[] memory actualTokenAmounts) {
        IVaultRegistry vaultRegistry = _vaultGovernance.internalParams().registry;
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        address[] memory tokens = _vaultTokens;
        uint256[] memory pulledAmounts = new uint256[](tokenAmounts.length);
        uint256[] memory existentials = _pullExistentials;
        uint256[] memory leftToPull = new uint256[](tokenAmounts.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            leftToPull[i] = tokenAmounts[i];
        }
        for (uint256 i = 0; i < _subvaultNfts.length; i++) {
            uint256 subvaultNft = _subvaultNfts[i];
            IIntegrationVault subvault = IIntegrationVault(vaultRegistry.vaultForNft(subvaultNft));
            pulledAmounts = subvault.pull(address(this), tokens, leftToPull, "");
            bool shouldStop = true;
            for (uint256 j = 0; j < tokens.length; j++) {
                if (leftToPull[j] > pulledAmounts[j] + existentials[j]) {
                    shouldStop = false;
                    leftToPull[j] -= pulledAmounts[j];
                } else {
                    leftToPull[j] = 0;
                }
                actualTokenAmounts[j] += pulledAmounts[j];
            }
            if (shouldStop) {
                break;
            }
        }
        address subvault0 = vaultRegistry.vaultForNft(_subvaultNfts[0]);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (tokenAmounts[i] < balance) {
                actualTokenAmounts[i] = tokenAmounts[i];
                IERC20(tokens[i]).safeTransfer(to, tokenAmounts[i]);
                IERC20(tokens[i]).safeTransfer(subvault0, balance - tokenAmounts[i]);
            } else {
                actualTokenAmounts[i] = balance;
                IERC20(tokens[i]).safeTransfer(to, balance);
            }
        }
    }
}
