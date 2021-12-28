// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./interfaces/IGatewayVault.sol";
import "./libraries/CommonLibrary.sol";
import "./interfaces/IVault.sol";
import "./VaultGovernance.sol";
import "./libraries/ExceptionsLibrary.sol";

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
abstract contract Vault is IVault, ERC165 {
    using SafeERC20 for IERC20;

    IVaultGovernance internal _vaultGovernance;
    address[] internal _vaultTokens;
    mapping(address => bool) internal _vaultTokensIndex;
    uint256 internal _nft;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance of this Vault
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param nft_ NFT of the vault in the VaultRegistry
    constructor(
        IVaultGovernance vaultGovernance_,
        address[] memory vaultTokens_,
        uint256 nft_
    ) {
        require(CommonLibrary.isSortedAndUnique(vaultTokens_), ExceptionsLibrary.SORTED_AND_UNIQUE);
        require(nft_ != 0, ExceptionsLibrary.NFT_ZERO);
        _vaultGovernance = vaultGovernance_;
        _vaultTokens = vaultTokens_;
        _nft = nft_;
        uint256 len = _vaultTokens.length;
        for (uint256 i = 0; i < len; ++i) _vaultTokensIndex[vaultTokens_[i]] = true;
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        registry.setApprovalForAll(address(registry), true);
    }

    // -------------------  PUBLIC, VIEW  -------------------

    function isVaultToken(address token) public view returns (bool) {
        return _vaultTokensIndex[token];
    }


    /// @inheritdoc IVault
    function vaultGovernance() external view returns (IVaultGovernance) {
        return _vaultGovernance;
    }

    /// @inheritdoc IVault
    function vaultTokens() external view returns (address[] memory) {
        return _vaultTokens;
    }

    /// @inheritdoc IVault
    function nft() external view returns (uint256) {
        return _nft;
    }

    /// @inheritdoc IVault
    function tvl() public view virtual returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts);

    function supportsInterface(bytes4 interfaceId) public view override(IERC165, ERC165) returns (bool) {
        return super.supportsInterface(interfaceId) || (interfaceId == type(IVault).interfaceId);
    }

    function _allowTokenIfNecessary(address token, address to) internal {
        if (IERC20(token).allowance(address(this), to) < type(uint256).max / 2) {
            IERC20(token).approve(to, type(uint256).max);
        }
    }

}
