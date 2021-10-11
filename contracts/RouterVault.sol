// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IVault.sol";
import "./Vault.sol";

contract RouterVault is Vault {
    using SafeERC20 for IERC20;
    address[] private _vaults;

    constructor(
        address[] memory tokens,
        IVaultManager vaultManager,
        address strategyTreasury
    ) Vault(tokens, vaultManager, strategyTreasury) {}

    function tvl() public view override returns (uint256[] memory tokenAmounts) {
        address[] memory tokens = vaultTokens();
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _vaults.length; i++) {
            IVault vault = IVault(_vaults[i]);
            address[] memory vTokens = vault.vaultTokens();
            uint256[] memory vTokenAmounts = vault.tvl();
            uint256[] memory pTokenAmounts = Common.projectTokenAmounts(tokens, vTokens, vTokenAmounts);
            for (uint256 j = 0; j < tokens.length; j++) {
                tokenAmounts[j] += pTokenAmounts[j];
            }
        }
    }

    function earnings() public view override returns (uint256[] memory tokenAmounts) {
        address[] memory tokens = vaultTokens();
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _vaults.length; i++) {
            IVault vault = IVault(_vaults[i]);
            address[] memory vTokens = vault.vaultTokens();
            uint256[] memory vTokenAmounts = vault.earnings();
            uint256[] memory pTokenAmounts = Common.projectTokenAmounts(tokens, vTokens, vTokenAmounts);
            for (uint256 j = 0; j < tokens.length; j++) {
                tokenAmounts[j] += pTokenAmounts[j];
            }
        }
    }

    function vaultTvl(uint256 vaultNum) public view returns (uint256[] memory) {
        IVault vault = IVault(_vaults[vaultNum]);
        address[] memory pTokens = vault.vaultTokens();
        uint256[] memory vTokenAmounts = vault.tvl();
        return Common.projectTokenAmounts(vaultTokens(), pTokens, vTokenAmounts);
    }

    function vaultsTvl() public view returns (uint256[][] memory tokenAmounts) {
        address[] memory tokens = vaultTokens();
        tokenAmounts = new uint256[][](_vaults.length);
        for (uint256 i = 0; i < _vaults.length; i++) {
            IVault vault = IVault(_vaults[i]);
            address[] memory vTokens = vault.vaultTokens();
            uint256[] memory vTokenAmounts = vault.tvl();
            uint256[] memory pTokenAmounts = Common.projectTokenAmounts(tokens, vTokens, vTokenAmounts);
            tokenAmounts[i] = new uint256[](tokens.length);
            for (uint256 j = 0; j < tokens.length; j++) {
                tokenAmounts[i][j] = pTokenAmounts[j];
            }
        }
    }

    function vaultEarnings(uint256 vaultNum) public view returns (uint256[] memory) {
        IVault vault = IVault(_vaults[vaultNum]);
        address[] memory pTokens = vault.vaultTokens();
        uint256[] memory vTokenAmounts = vault.earnings();
        return Common.projectTokenAmounts(vaultTokens(), pTokens, vTokenAmounts);
    }

    function _push(uint256[] memory tokenAmounts) internal override returns (uint256[] memory actualTokenAmounts) {
        uint256[][] memory tvls = vaultsTvl();
        address[] memory tokens = vaultTokens();
        uint256[][] memory amountsByVault = Common.splitAmounts(tokenAmounts, tvls);
        actualTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _vaults.length; i++) {
            IVault vault = IVault(_vaults[i]);
            uint256[] memory actualVaultTokenAmounts = vault.push(tokens, amountsByVault[i]);
            for (uint256 j = 0; j < tokens.length; j++) {
                actualTokenAmounts[j] += actualVaultTokenAmounts[j];
            }
        }
    }

    function _pull(address to, uint256[] memory tokenAmounts)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        uint256[][] memory tvls = vaultsTvl();
        address[] memory tokens = vaultTokens();
        uint256[][] memory amountsByVault = Common.splitAmounts(tokenAmounts, tvls);
        actualTokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < _vaults.length; i++) {
            IVault vault = IVault(_vaults[i]);
            uint256[] memory actualVaultTokenAmounts = vault.pull(to, tokens, amountsByVault[i]);
            for (uint256 j = 0; j < tokens.length; j++) {
                actualTokenAmounts[j] += actualVaultTokenAmounts[j];
            }
        }
    }

    function _collectEarnings(address to) internal override returns (uint256[] memory collectedEarnings) {
        address[] memory tokens = vaultTokens();
        collectedEarnings = new uint256[](tokens.length);
        for (uint256 i = 0; i < _vaults.length; i++) {
            IVault vault = IVault(_vaults[i]);
            address[] memory vTokens = vault.vaultTokens();
            uint256[] memory vTokenAmounts = vault.collectEarnings(address(this));
            uint256[] memory pTokenAmounts = Common.projectTokenAmounts(tokens, vTokens, vTokenAmounts);
            for (uint256 j = 0; j < tokens.length; j++) {
                collectedEarnings[j] += pTokenAmounts[j];
            }
        }
        uint256[] memory fees = _collectFees(collectedEarnings);
        for (uint256 i = 0; i < tokens.length; i++) {
            collectedEarnings[i] -= fees[i];
            IERC20(tokens[i]).safeTransfer(to, collectedEarnings[i]);
        }
    }

    function _collectFees(uint256[] memory collectedEarnings) internal returns (uint256[] memory collectedFees) {
        address[] memory tokens = vaultTokens();
        collectedFees = new uint256[](tokens.length);
        IProtocolGovernance governance = vaultManager().governanceParams().protocolGovernance;
        address protocolTres = governance.protocolTreasury();
        uint256 protocolPerformanceFee = governance.protocolPerformanceFee();
        uint256 strategyPerformanceFee = governance.strategyPerformanceFee();
        address strategyTres = strategyTreasury();
        uint256[] memory strategyFees = new uint256[](tokens.length);
        uint256[] memory protocolFees = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            protocolFees[i] = (collectedEarnings[i] * protocolPerformanceFee) / Common.DENOMINATOR;
            strategyFees[i] = (collectedEarnings[i] * strategyPerformanceFee) / Common.DENOMINATOR;
            token.safeTransfer(strategyTres, strategyFees[i]);
            token.safeTransfer(protocolTres, protocolFees[i]);
            collectedFees[i] = protocolFees[i] + strategyFees[i];
        }
        emit CollectStrategyFees(strategyTres, tokens, strategyFees);
        emit CollectProtocolFees(protocolTres, tokens, protocolFees);
    }

    event CollectProtocolFees(address protocolTreasury, address[] tokens, uint256[] amounts);
    event CollectStrategyFees(address strategyTreasury, address[] tokens, uint256[] amounts);
}
