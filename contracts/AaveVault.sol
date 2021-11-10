// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/external/aave/ILendingPool.sol";
import "./interfaces/IAaveVaultGovernance.sol";
import "./Vault.sol";

/// @notice Vault that interfaces Aave protocol in the integration layer
contract AaveVault is Vault {
    address[] private _aTokens;
    uint256[] private _baseBalances;

    /// @notice Creates a new contract
    /// @param vaultGovernance_ Reference to VaultGovernance for this vault
    /// @param vaultTokens_ ERC20 tokens under Vault management
    constructor(IVaultGovernance vaultGovernance_, address[] memory vaultTokens_)
        Vault(vaultGovernance_, vaultTokens_)
    {
        _aTokens = new address[](vaultTokens_.length);
        for (uint256 i = 0; i < _vaultTokens.length; i++) {
            _aTokens[i] = _getAToken(_vaultTokens[i]);
        }
    }

    /// @inheritdoc Vault
    function tvl() public view override returns (uint256[] memory tokenAmounts) {
        address[] memory tokens = _vaultTokens;
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _aTokens.length; i++) {
            address aToken = _aTokens[i];
            tokenAmounts[i] = IERC20(aToken).balanceOf(address(this));
        }
    }

    /// @inheritdoc Vault
    function earnings() public view override returns (uint256[] memory tokenAmounts) {
        address[] memory tokens = _vaultTokens;
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _aTokens.length; i++) {
            address aToken = _aTokens[i];
            uint256 balance = IERC20(aToken).balanceOf(address(this));
            tokenAmounts[i] = balance - _baseBalances[i];
        }
    }

    function _push(
        uint256[] memory tokenAmounts,
        bool,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < _aTokens.length; i++) {
            if (tokenAmounts[i] == 0) {
                continue;
            }
            address aToken = _aTokens[i];
            address token = tokens[i];
            _allowTokenIfNecessary(token);
            uint256 baseTokensToMint;
            if (_baseBalances[i] == 0) {
                baseTokensToMint = tokenAmounts[i];
            } else {
                baseTokensToMint = (tokenAmounts[i] * _baseBalances[i]) / IERC20(aToken).balanceOf(address(this));
            }

            // TODO: Check what is 0
            _lendingPool().deposit(tokens[i], tokenAmounts[i], address(this), 0);
            _baseBalances[i] += baseTokensToMint;
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bool,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < _aTokens.length; i++) {
            address aToken = _aTokens[i];
            uint256 balance = IERC20(aToken).balanceOf(address(this));
            if (balance == 0) {
                continue;
            }
            uint256 tokensToBurn = (tokenAmounts[i] * _baseBalances[i]) / balance;
            if (tokensToBurn == 0) {
                continue;
            }
            _baseBalances[i] -= tokensToBurn;
            _lendingPool().withdraw(tokens[i], tokenAmounts[i], to);
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _collectEarnings(address to, bytes memory) internal override returns (uint256[] memory collectedEarnings) {
        collectedEarnings = earnings();
        address[] memory tokens = _vaultTokens;
        for (uint256 i = 0; i < _aTokens.length; i++) {
            _lendingPool().withdraw(tokens[i], collectedEarnings[i], to);
        }
    }

    function _getAToken(address token) internal view returns (address) {
        DataTypes.ReserveData memory data = _lendingPool().getReserveData(token);
        return data.aTokenAddress;
    }

    function _allowTokenIfNecessary(address token) internal {
        if (IERC20(token).allowance(address(_lendingPool()), address(this)) < type(uint256).max / 2) {
            IERC20(token).approve(address(_lendingPool()), type(uint256).max);
        }
    }

    function _lendingPool() internal view returns (ILendingPool) {
        return IAaveVaultGovernance(address(_vaultGovernance)).delayedProtocolParams().lendingPool;
    }
}
