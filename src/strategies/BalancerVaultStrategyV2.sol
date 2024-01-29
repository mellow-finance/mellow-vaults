// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/utils/ILpCallback.sol";

import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IBalancerV2VaultGovernance.sol";

import {IVault as IBalancerVault} from "../interfaces/external/balancer/vault/IVault.sol";
import {IBalancerMinter} from "../interfaces/external/balancer/liquidity-mining/IBalancerMinter.sol";

import "../vaults/BalancerV2CSPVault.sol";

import "../utils/ContractMeta.sol";
import "../utils/DefaultAccessControlLateInit.sol";

contract BalancerVaultStrategyV2 is ContractMeta, ILpCallback, DefaultAccessControlLateInit {
    using SafeERC20 for IERC20;

    IERC20Vault public erc20Vault;
    IBalancerV2Vault public subvault;
    address public swapRouter;

    address[] private _rewardTokens;

    function rewardTokens() public view returns (address[] memory) {
        return _rewardTokens;
    }

    constructor() {
        DefaultAccessControlLateInit.init(address(this));
    }

    function initialize(
        address admin,
        IERC20Vault erc20Vault_,
        address subvault_,
        address swapRouter_
    ) external {
        erc20Vault = erc20Vault_;
        subvault = IBalancerV2Vault(subvault_);
        swapRouter = swapRouter_;

        DefaultAccessControlLateInit(address(this)).init(admin);
    }

    function _transferAndSwapBALToken(uint256 minAmountOut) private returns (uint256 recievedAmount) {
        address bal = 0x4158734D47Fc9692176B5085E0F52ee0Da5d47F1;
        {
            uint256 subvaultAmount = IERC20(bal).balanceOf(address(subvault));
            if (subvaultAmount > 0) {
                subvault.externalCall(bal, IERC20.transfer.selector, abi.encode(address(this), subvaultAmount));
            }
        }
        uint256 amount = IERC20(bal).balanceOf(address(this));
        if (amount == 0) return 0;

        address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address weth = 0x4200000000000000000000000000000000000006;
        address balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        bytes32 balToUsdcPoolId = 0xb328b50f1f7d97ee8ea391ab5096dd7657555f49000100000000000000000048;
        bytes32 usdcToWethPoolId = 0x433f09ca08623e48bac7128b7105de678e37d988000100000000000000000047;

        IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](2);
        swaps[0] = IBalancerVault.BatchSwapStep({
            poolId: balToUsdcPoolId,
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: amount,
            userData: new bytes(0)
        });
        swaps[1] = IBalancerVault.BatchSwapStep({
            poolId: usdcToWethPoolId,
            assetInIndex: 1,
            assetOutIndex: 2,
            amount: 0,
            userData: new bytes(0)
        });

        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(bal);
        assets[1] = IAsset(usdc);
        assets[2] = IAsset(weth);

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(erc20Vault)),
            toInternalBalance: false
        });

        int256[] memory limits = new int256[](assets.length);
        limits[0] = int256(amount);
        limits[limits.length - 1] = -int256(minAmountOut);

        IERC20(bal).safeApprove(balancerVault, type(uint256).max);
        int256[] memory swappedAmounts = IBalancerVault(balancerVault).batchSwap(
            IBalancerVault.SwapKind.GIVEN_IN,
            swaps,
            assets,
            funds,
            limits,
            type(uint256).max
        );
        IERC20(bal).safeApprove(balancerVault, 0);
        recievedAmount = uint256(-swappedAmounts[swappedAmounts.length - 1]);
    }

    function compound(
        bytes[] memory swapParams,
        uint256 minAmountOut,
        uint256 deadline
    ) external returns (uint256 amountOut, uint256[] memory tokenAmounts) {
        _requireAtLeastOperator();
        require(deadline >= block.timestamp, ExceptionsLibrary.LIMIT_OVERFLOW);

        address[] memory rewardTokens_ = _rewardTokens;
        require(swapParams.length == rewardTokens_.length, ExceptionsLibrary.INVALID_LENGTH);

        try subvault.claimBalancerRewardToken() returns (uint256) {} catch {}
        try subvault.claimRewards() {} catch {}

        address balancerMinter = 0x0c5538098EBe88175078972F514C9e101D325D4F;
        try
            subvault.externalCall(
                balancerMinter,
                IBalancerMinter.mint.selector,
                abi.encode(BalancerV2CSPVault(address(subvault)).stakingLiquidityGauge())
            )
        {
            amountOut = _transferAndSwapBALToken(minAmountOut);
        } catch {}

        for (uint256 i = 0; i < swapParams.length; i++) {
            uint256 balance = IERC20(rewardTokens_[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(rewardTokens_[i]).safeIncreaseAllowance(swapRouter, balance);
                (bool success, ) = swapRouter.call(swapParams[i]);
                if (!success) revert("Swap of reward token failed");
                IERC20(rewardTokens_[i]).safeApprove(swapRouter, 0);
            }
        }

        address[] memory tokens = erc20Vault.vaultTokens();
        tokenAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                tokenAmounts[i] = balance;
                IERC20(tokens[i]).safeTransfer(address(erc20Vault), balance);
            }
        }
    }

    function setRewardTokens(address[] memory rewardTokens_) external {
        _requireAdmin();
        _rewardTokens = rewardTokens_;
    }

    function setStrategyParams(IBalancerV2VaultGovernance.StrategyParams memory strategyParams) external {
        _requireAdmin();
        IBalancerV2VaultGovernance(address(subvault.vaultGovernance())).setStrategyParams(
            subvault.nft(),
            strategyParams
        );
    }

    function upgradeStakingLiquidityGauge(address newGauge) external {
        _requireAdmin();
        BalancerV2CSPVault(address(subvault)).upgradeStakingLiquidityGauge(newGauge);
    }

    /// @inheritdoc ILpCallback
    function depositCallback() external {
        (uint256[] memory tokenAmounts, ) = erc20Vault.tvl();
        if (tokenAmounts[0] > 0 || tokenAmounts[1] > 0) {
            erc20Vault.pull(address(subvault), erc20Vault.vaultTokens(), tokenAmounts, "");
        }
    }

    /// @inheritdoc ILpCallback
    function withdrawCallback() external {}

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("BalancerVaultStrategy");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
