// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/external/aave/ILendingPool.sol";
import "./interfaces/external/yearn/IYearnVault.sol";
import "./interfaces/IYearnVaultGovernance.sol";
import "./Vault.sol";

/// @notice Vault that interfaces Yearn protocol in the integration layer.
contract YearnVault is Vault {
    address[] private _yTokens;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        Vault(vaultGovernance_, vaultTokens_)
    {
        _yTokens = new address[](vaultTokens_.length);
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            _yTokens[i] = _yearnVaultRegistry().latestVault(_vaultTokens[i]);
            require(_yTokens[i] != address(0), "VDE");
        }
    }

    /// @inheritdoc Vault
    function tvl() public view override returns (uint256[] memory tokenAmounts) {
        address[] memory tokens = _vaultTokens;
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _yTokens.length; i++) {
            IYearnVault yToken = _yTokens[i];
            /// TODO: Verify it's not subject to manipulation like in Cream hack
            tokenAmounts[i] = (yToken.balanceOf(address(this)) * yToken.pricePerShare()) / yToken.decimals();
        }
    }

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < _yTokens.length; i++) {
            if (tokenAmounts[i] == 0) {
                continue;
            }
            address yToken = _yTokens[i];
            address token = tokens[i];
            _allowTokenIfNecessary(token);
            uint256 baseTokensToMint;
            if (_baseBalances[i] == 0) {
                baseTokensToMint = tokenAmounts[i];
            } else {
                baseTokensToMint = (tokenAmounts[i] * _baseBalances[i]) / IERC20(yToken).balanceOf(address(this));
            }

            // TODO: Check what is 0
            _yearnVaultRegistry().deposit(tokens[i], tokenAmounts[i], address(this), 0);
            _baseBalances[i] += baseTokensToMint;
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < _yTokens.length; i++) {
            address yToken = _yTokens[i];
            uint256 balance = IERC20(yToken).balanceOf(address(this));
            if (balance == 0) {
                continue;
            }
            uint256 tokensToBurn = (tokenAmounts[i] * _baseBalances[i]) / balance;
            if (tokensToBurn == 0) {
                continue;
            }
            _baseBalances[i] -= tokensToBurn;
            _yearnVaultRegistry().withdraw(tokens[i], tokenAmounts[i], to);
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _getAToken(address token) internal view returns (address) {
        DataTypes.ReserveData memory data = _yearnVaultRegistry().getReserveData(token);
        return data.yTokenAddress;
    }

    function _allowTokenIfNecessary(address token) internal {
        if (IERC20(token).allowance(address(_yearnVaultRegistry()), address(this)) < type(uint256).max / 2) {
            IERC20(token).approve(address(_yearnVaultRegistry()), type(uint256).max);
        }
    }

    function _yearnVaultRegistry() internal view returns (IYearnVaultRegistry) {
        return IYearnVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().yearnVaultRegistry;
    }
}
