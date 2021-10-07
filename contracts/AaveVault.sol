// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/external/aave/ILendingPool.sol";
import "./interfaces/IAaveVaultManager.sol";
import "./Vault.sol";

contract AaveVault is Vault {
    address[] private _aTokens;
    mapping(address => uint256) private _baseBalances;

    constructor(
        address[] memory tokens,
        uint256[] memory limits,
        IVaultManager vaultManager
    ) Vault(tokens, limits, vaultManager) {
        for (uint256 i = 0; i < tokens.length; i++) {
            _aTokens[i] = _getAToken(tokens[i]);
        }
    }

    function tvl() public view override returns (address[] memory tokens, uint256[] memory tokenAmounts) {
        tokens = vaultTokens();
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _aTokens.length; i++) {
            address aToken = _aTokens[i];
            tokenAmounts[i] = IERC20(aToken).balanceOf(address(this));
        }
    }

    function _push(uint256[] memory tokenAmounts) internal override returns (uint256[] memory actualTokenAmounts) {
        address[] memory tokens = vaultTokens();
        for (uint256 i = 0; i < _aTokens.length; i++) {
            if (tokenAmounts[i] == 0) {
                continue;
            }
            address aToken = _aTokens[i];
            address token = tokens[i];
            _allowTokenIfNecessary(token);
            uint256 baseTokensToMint;
            if (_baseBalances[tokens[i]] == 0) {
                baseTokensToMint = tokenAmounts[i];
            } else {
                baseTokensToMint = (tokenAmounts[i] * _baseBalances[token]) / IERC20(aToken).balanceOf(address(this));
            }

            // TODO: Check what is 0
            _lendingPool().deposit(tokens[i], tokenAmounts[i], address(this), 0);
            _baseBalances[tokens[i]] += baseTokensToMint;
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _pull(address to, uint256[] memory tokenAmounts)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        address[] memory tokens = vaultTokens();
        for (uint256 i = 0; i < _aTokens.length; i++) {
            address aToken = _aTokens[i];
            address token = tokens[i];
            uint256 balance = IERC20(aToken).balanceOf(address(this));
            if (balance == 0) {
                continue;
            }
            uint256 tokensToBurn = (tokenAmounts[i] * _baseBalances[token]) / balance;
            if (tokensToBurn == 0) {
                continue;
            }
            _baseBalances[token] -= tokensToBurn;
            _lendingPool().withdraw(tokens[i], tokenAmounts[i], to);
        }
        actualTokenAmounts = tokenAmounts;
    }

    function _collectEarnings(address, address[] memory tokens)
        internal
        pure
        override
        returns (uint256[] memory collectedEarnings)
    {
        // no-op, no earnings here
        // IProtocolGovernance governance = vaultManager().protocolGovernance;
        // uint256 procotolFee = governance.protocolFee();
        // address procotolTreasury = governance.protocolTreasury();
        // VaultParams memory params = vaultParams(nft);
        // uint256 vaultFee = params.fee;
        // address vaultFeeReceiver = params.feeReceiver;
        // collectedEarnings = new uint256[](tokens.length);
        // for (uint256 i = 0; i < tokens.length; i++) {
        //     IERC20 aToken = _getAToken(IERC20(tokens[i]));
        //     uint256 aBalance = aToken.balanceOf(address(this));
        // }
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
        return IAaveVaultManager(address(vaultManager())).lendingPool();
    }
}
