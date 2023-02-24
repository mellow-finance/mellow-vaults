// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/external/convex/Interfaces.sol";
import "../interfaces/external/gearbox/helpers/IPriceOracle.sol";
import "../libraries/external/FullMath.sol";
import "../interfaces/external/gearbox/IConvexV1BaseRewardPoolAdapter.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IGearboxVaultGovernance.sol";
import "../interfaces/oracles/IOracle.sol";
import "../interfaces/external/gearbox/helpers/IPoolService.sol";
import "../interfaces/vaults/IGearboxERC20Vault.sol";
import "../interfaces/utils/IGearboxERC20Helper.sol";
import "../interfaces/external/gearbox/helpers/ICreditAccount.sol";
import "./GearboxHelper.sol";

contract GearboxERC20Helper is IGearboxERC20Helper {

    uint256 public constant D27 = 10**27;
    uint256 public constant Q96 = 2**96;

    function calcTvl(address[] memory _vaultTokens) public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {

        IGearboxERC20Vault vault = IGearboxERC20Vault(msg.sender);

        minTokenAmounts = new uint256[](1);

        IERC20 token = IERC20(_vaultTokens[0]);
        minTokenAmounts[0] = vault.totalDeposited();

        if (vault.vaultsCount() == 0) {
            return (minTokenAmounts, minTokenAmounts);
        }

        ICreditManagerV2 creditManager;
        GearboxHelper helper;
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams;
        address primaryToken;

        {

            IGearboxVault sampleVault = IGearboxVault(vault.subvaultsList(0));

            creditManager = sampleVault.creditManager();
            helper = sampleVault.helper();
            protocolParams = IGearboxVaultGovernance(
                address(sampleVault.vaultGovernance())
            ).delayedProtocolParams();
            primaryToken = sampleVault.primaryToken();

        }

        address depositToken = address(token);
        IOracle mellowOracle = helper.mellowOracle();

        uint256 totalPrimaryTokenAmount;

        {
            if (depositToken != primaryToken) {
                for (uint256 i = 0; i < vault.vaultsCount(); ++i) {
                    address ca = IGearboxVault(vault.subvaultsList(i)).getCreditAccount();
                    if (ca != address(0)) {
                        minTokenAmounts[0] += token.balanceOf(ca);
                    }
                    minTokenAmounts[0] += token.balanceOf(vault.subvaultsList(i));
                }
            }

            for (uint256 i = 0; i < vault.vaultsCount(); ++i) {
                totalPrimaryTokenAmount += IERC20(primaryToken).balanceOf(vault.subvaultsList(i));
            }
        }

        {
            totalPrimaryTokenAmount += helper.calcTotalWithdraw(vault.totalConvexLpTokens());
        }

        {
            uint256 totalBorrowedWithInterest = FullMath.mulDiv(
                vault.cumulativeSumRAY(),
                IPoolService(creditManager.pool()).calcLinearCumulative_RAY(),
                D27
            );
            (uint16 feeInterest, , , , ) = creditManager.fees();
            if (totalBorrowedWithInterest > vault.totalBorrowedAmount()) {
                totalPrimaryTokenAmount -= FullMath.mulDiv(
                    totalBorrowedWithInterest - vault.totalBorrowedAmount(),
                    uint256(feeInterest),
                    10000
                );
            }

            totalPrimaryTokenAmount -= totalBorrowedWithInterest;
        }

        {
            IPriceOracleV2 oracle = helper.oracle();
            uint256 totalCRV = vault.totalEarnedCRV();
            uint256 rewardPerToken = IConvexV1BaseRewardPoolAdapter(vault.convexAdapter()).rewardPerToken();
            totalCRV += (vault.cumulativeSumCRV() * rewardPerToken - vault.cumulativeSubCRV()) / 10**18;
            totalPrimaryTokenAmount += oracle.convert(totalCRV, protocolParams.crv, primaryToken);
            {
                uint256 totalCVX = helper.calculateEarnedCvxAmountByEarnedCrvAmount(totalCRV, protocolParams.cvx);
                totalPrimaryTokenAmount += oracle.convert(totalCVX, protocolParams.cvx, primaryToken);
            }
        }

        {
            IBaseRewardPool underlyingContract = IBaseRewardPool(creditManager.adapterToContract(vault.convexAdapter()));
            if (underlyingContract.extraRewardsLength() > 0) {
                IBaseRewardPool rewardsContract = IBaseRewardPool(underlyingContract.extraRewards(0));
                uint256 rewardPerTokenLDO = rewardsContract.rewardPerToken();
                uint256 totalLDO = vault.totalEarnedLDO() + (vault.cumulativeSumLDO() * rewardPerTokenLDO - vault.cumulativeSubLDO()) / 10**18;

                (uint256[] memory pricesX96, ) = mellowOracle.priceX96(
                    address(rewardsContract.rewardToken()),
                    primaryToken,
                    0x20
                );
                if (pricesX96.length != 0) {
                    totalPrimaryTokenAmount += FullMath.mulDiv(totalLDO, pricesX96[0], Q96);
                }
            }
        }

        IPriceOracleV2 gOracle = helper.oracle();

        if (depositToken != primaryToken) {
            minTokenAmounts[0] += gOracle.convert(totalPrimaryTokenAmount, primaryToken, depositToken);
        } else {
            minTokenAmounts[0] += totalPrimaryTokenAmount;
        }

        maxTokenAmounts = minTokenAmounts;
    }

}