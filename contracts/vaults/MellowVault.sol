// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import "../interfaces/vaults/IMellowVault.sol";
import "../interfaces/vaults/IERC20RootVault.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";

/// @notice Vault that stores ERC20 tokens.
contract MellowVault is IMellowVault, IntegrationVault {
    using SafeERC20 for IERC20;

    /// @inheritdoc IMellowVault
    IERC20RootVault public vault;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        IERC20RootVault vault_ = vault;
        uint256 balance = vault_.balanceOf(address(this));
        uint256 supply = vault_.totalSupply();
        (minTokenAmounts, maxTokenAmounts) = vault_.tvl();
        for (uint256 i = 0; i < minTokenAmounts.length; i++) {
            minTokenAmounts[i] = FullMath.mulDiv(balance, minTokenAmounts[i], supply);
            maxTokenAmounts[i] = FullMath.mulDiv(balance, maxTokenAmounts[i], supply);
        }
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IMellowVault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        IERC20RootVault vault_
    ) external {
        _initialize(vaultTokens_, nft_);
        address[] memory mTokens = vault_.vaultTokens();
        for (uint256 i = 0; i < vaultTokens_.length; i++) {
            require(mTokens[i] == vaultTokens_[i], ExceptionsLibrary.INVALID_TOKEN);
        }
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        require(registry.nftForVault(address(vault)) > 0, ExceptionsLibrary.INVALID_INTERFACE);
        vault = vault_;
    }

    // -------------------  INTERNAL, VIEW  -----------------------
    function _isReclaimForbidden(address token) internal view override returns (bool) {
        address[] memory mTokens = vault.vaultTokens();
        for (uint256 i = 0; i < mTokens.length; ++i) {
            if (mTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory options)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        uint256 minLpTokens;
        assembly {
            minLpTokens := mload(add(options, 0x20))
        }
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            IERC20(_vaultTokens[i]).safeIncreaseAllowance(address(vault), tokenAmounts[i]);
        }
        actualTokenAmounts = vault.deposit(tokenAmounts, minLpTokens, "");
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            IERC20(_vaultTokens[i]).safeApprove(address(vault), 0);
        }
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        IERC20RootVault vault_ = vault;
        uint256[] memory minTokenAmounts = abi.decode(options, (uint256[]));
        (uint256[] memory minTvl, ) = tvl();
        uint256 totalLpTokens = vault.balanceOf(address(this));
        uint256 lpTokenAmount = type(uint256).max;
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            uint256 newAmount = FullMath.mulDiv(totalLpTokens, tokenAmounts[i], minTvl[i]);
            if (newAmount < lpTokenAmount) {
                lpTokenAmount = newAmount;
            }
        }
        if (lpTokenAmount > totalLpTokens) {
            lpTokenAmount = totalLpTokens;
        }

        bytes[] memory emptyOptions = new bytes[](vault.subvaultNfts().length);
        for (uint256 i = 0; i < emptyOptions.length; ++i) {
            emptyOptions[i] = "";
        }
        actualTokenAmounts = vault_.withdraw(to, lpTokenAmount, minTokenAmounts, emptyOptions);
    }
}
