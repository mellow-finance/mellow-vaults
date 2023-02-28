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

    uint256 public totalConvexLpTokens;
    mapping(address => uint256) public convexLpTokensMapping;

    uint256 public cumulativeSumRAY;
    mapping(address => uint256) public sumRAYMapping;

    uint256 public totalBorrowedAmount;
    mapping(address => uint256) public borrowedAmountMapping;

    uint256 public totalEarnedCRV;
    mapping(address => uint256) public earnedCRVMapping;

    uint256 public cumulativeSumCRV;
    mapping(address => uint256) public sumCRVMapping;

    uint256 public cumulativeSubCRV;
    mapping(address => uint256) public subCRVMapping;

    uint256 public totalEarnedLDO;
    mapping(address => uint256) public earnedLDOMapping;

    uint256 public cumulativeSumLDO;
    mapping(address => uint256) public sumLDOMapping;

    uint256 public cumulativeSubLDO;
    mapping(address => uint256) public subLDOMapping;

    address public admin;

    constructor(address admin_) {
        admin = admin_;
    }

    function calcTvl(address[] memory _vaultTokens)
        public
        view
        returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts)
    {
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
            protocolParams = IGearboxVaultGovernance(address(sampleVault.vaultGovernance())).delayedProtocolParams();
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
            totalPrimaryTokenAmount += helper.calcTotalWithdraw(totalConvexLpTokens);
        }

        {
            uint256 totalBorrowedWithInterest = FullMath.mulDiv(
                cumulativeSumRAY,
                IPoolService(creditManager.pool()).calcLinearCumulative_RAY(),
                D27
            );
            (uint16 feeInterest, , , , ) = creditManager.fees();
            if (totalBorrowedWithInterest > totalBorrowedAmount) {
                totalPrimaryTokenAmount -= FullMath.mulDiv(
                    totalBorrowedWithInterest - totalBorrowedAmount,
                    uint256(feeInterest),
                    10000
                );
            }

            totalPrimaryTokenAmount -= totalBorrowedWithInterest;
        }

        {
            IPriceOracleV2 oracle = helper.oracle();
            uint256 totalCRV = totalEarnedCRV;
            uint256 rewardPerToken = IConvexV1BaseRewardPoolAdapter(vault.convexAdapter()).rewardPerToken();
            totalCRV += (cumulativeSumCRV * rewardPerToken - cumulativeSubCRV) / 10**18;
            totalPrimaryTokenAmount += oracle.convert(totalCRV, protocolParams.crv, primaryToken);
            {
                uint256 totalCVX = helper.calculateEarnedCvxAmountByEarnedCrvAmount(totalCRV, protocolParams.cvx);
                totalPrimaryTokenAmount += oracle.convert(totalCVX, protocolParams.cvx, primaryToken);
            }
        }

        {
            IBaseRewardPool underlyingContract = IBaseRewardPool(
                creditManager.adapterToContract(vault.convexAdapter())
            );
            if (underlyingContract.extraRewardsLength() > 0) {
                IBaseRewardPool rewardsContract = IBaseRewardPool(underlyingContract.extraRewards(0));
                uint256 rewardPerTokenLDO = rewardsContract.rewardPerToken();
                uint256 totalLDO = totalEarnedLDO + (cumulativeSumLDO * rewardPerTokenLDO - cumulativeSubLDO) / 10**18;

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

    function removeParameters(address addr) external {
        require(msg.sender == admin, ExceptionsLibrary.FORBIDDEN);

        totalConvexLpTokens -= convexLpTokensMapping[addr];
        convexLpTokensMapping[addr] = 0;

        cumulativeSumRAY -= sumRAYMapping[addr];
        sumRAYMapping[addr] = 0;

        totalBorrowedAmount -= borrowedAmountMapping[addr];
        borrowedAmountMapping[addr] = 0;

        totalEarnedCRV -= earnedCRVMapping[addr];
        earnedCRVMapping[addr] = 0;

        cumulativeSumCRV -= sumCRVMapping[addr];
        sumCRVMapping[addr] = 0;

        cumulativeSubCRV -= subCRVMapping[addr];
        subCRVMapping[addr] = 0;

        totalEarnedLDO -= earnedLDOMapping[addr];
        earnedLDOMapping[addr] = 0;

        cumulativeSumLDO -= sumLDOMapping[addr];
        sumLDOMapping[addr] = 0;

        cumulativeSubLDO -= subLDOMapping[addr];
        subLDOMapping[addr] = 0;
    }

    function addParameters(address addr) external {
        require(msg.sender == admin, ExceptionsLibrary.FORBIDDEN);

        IGearboxERC20Vault parentVault = IGearboxERC20Vault(msg.sender);

        uint256 W;

        IGearboxVault vault = IGearboxVault(addr);
        GearboxHelper gearboxHelper = vault.helper();

        ICreditAccount ca = ICreditAccount(vault.getCreditAccount());
        if (address(ca) == address(0)) {
            return;
        }

        IConvexV1BaseRewardPoolAdapter convexAdapterContract = IConvexV1BaseRewardPoolAdapter(
            address(parentVault.convexAdapter())
        );

        W = IERC20(gearboxHelper.convexOutputToken()).balanceOf(address(ca));
        convexLpTokensMapping[addr] = W;
        totalConvexLpTokens += W;

        W = ca.borrowedAmount();
        borrowedAmountMapping[addr] = W;
        totalBorrowedAmount += W;

        W = FullMath.mulDiv(W, D27, ca.cumulativeIndexAtOpen());
        sumRAYMapping[addr] = W;
        cumulativeSumRAY += W;

        W = convexAdapterContract.rewards(address(ca));
        earnedCRVMapping[addr] = W;
        totalEarnedCRV += W;

        W = convexAdapterContract.balanceOf(address(ca));
        sumCRVMapping[addr] = W;
        cumulativeSumCRV += W;

        W = convexAdapterContract.balanceOf(address(ca)) * convexAdapterContract.userRewardPerTokenPaid(address(ca));
        subCRVMapping[addr] = W;
        cumulativeSubCRV += W;

        IBaseRewardPool underlyingContract = IBaseRewardPool(
            vault.creditManager().adapterToContract(address(parentVault.convexAdapter()))
        );
        if (underlyingContract.extraRewardsLength() > 0) {
            IBaseRewardPool rewardsContract = IBaseRewardPool(underlyingContract.extraRewards(0));

            W = rewardsContract.rewards(address(ca));
            earnedLDOMapping[addr] = W;
            totalEarnedLDO += W;

            W = rewardsContract.balanceOf(address(ca));
            sumLDOMapping[addr] = W;
            cumulativeSumLDO += W;

            W = rewardsContract.balanceOf(address(ca)) * rewardsContract.userRewardPerTokenPaid(address(ca));
            subLDOMapping[addr] = W;
            cumulativeSubLDO += W;
        }
    }
}
