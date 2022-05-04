// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IProtocolGovernance.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "./IntegrationVault.sol";
import "hardhat/console.sol";

/// @notice Vault that stores ERC20 tokens.
contract ERC20Vault is IERC20Vault, IntegrationVault {
    using SafeERC20 for IERC20;

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IVault
    function tvl() public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        address[] memory tokens = _vaultTokens;
        uint256 len = tokens.length;
        minTokenAmounts = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            minTokenAmounts[i] = IERC20(tokens[i]).balanceOf(address(this));
        }
        maxTokenAmounts = minTokenAmounts;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------
    /// @inheritdoc IERC20Vault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        _initialize(vaultTokens_, nft_);
    }

    // @inheritdoc IIntegrationVault
    function reclaimTokens(address[] memory tokens)
        external
        override(IIntegrationVault, IntegrationVault)
        nonReentrant
        returns (uint256[] memory actualTokenAmounts)
    {
        // no-op
        actualTokenAmounts = new uint256[](tokens.length);
    }

    // -------------------  INTERNAL, MUTATING  -------------------

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        // no-op, tokens are already on balance
        return tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory options
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        actualTokenAmounts = new uint256[](tokenAmounts.length);
        address[] memory tokens = _vaultTokens;
        IVaultRegistry registry = _vaultGovernance.internalParams().registry;
        address owner = registry.ownerOf(_nft);

        for (uint256 i = 0; i < tokenAmounts.length; ++i) {
            IERC20 vaultToken = IERC20(_vaultTokens[i]);
            uint256 balance = vaultToken.balanceOf(address(this));
            uint256 amount = tokenAmounts[i] < balance ? tokenAmounts[i] : balance;
            IERC20(_vaultTokens[i]).safeTransfer(to, amount);
            if (owner != to) {
                // this will equal to amounts pulled + any accidental prior balances on `to`;
                actualTokenAmounts[i] = IERC20(_vaultTokens[i]).balanceOf(to);
            } else {
                actualTokenAmounts[i] = amount;
            }
        }
        if (owner != to) {
            // if we pull as a strategy, make sure everything is pushed
            console.log("WE WERE HERE");
            IIntegrationVault(to).push(tokens, actualTokenAmounts, options);
            console.log("WE WERE HERE 2");
            // any accidental prior balances + push leftovers
            uint256[] memory reclaimed = IIntegrationVault(to).reclaimTokens(tokens);
            console.log("WE WERE HERE 3");
            for (uint256 i = 0; i < tokenAmounts.length; i++) {
                // equals to exactly how much is pushed
                actualTokenAmounts[i] -= reclaimed[i];
            }
            console.log("WE WERE HERE 4");
        }
    }
}
