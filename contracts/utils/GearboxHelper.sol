// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/external/convex/ICvx.sol";
import "../interfaces/external/gearbox/helpers/ICreditManagerV2.sol";
import "../interfaces/external/gearbox/helpers/IPriceOracle.sol";
import "../libraries/external/FullMath.sol";
import "../interfaces/external/gearbox/ICreditFacade.sol";
import "../interfaces/external/gearbox/ICurveV1Adapter.sol";
import "../interfaces/external/gearbox/IConvexV1BaseRewardPoolAdapter.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IGearboxVaultGovernance.sol";
import "../interfaces/vaults/IGearboxVault.sol";
import "../interfaces/external/gearbox/IUniswapV3Adapter.sol";
import "../interfaces/external/gearbox/helpers/convex/IBooster.sol";

contract GearboxHelper {
    using SafeERC20 for IERC20;

    uint256 public constant D9 = 10**9;
    uint256 public constant D27 = 10**27;
    bytes4 public constant GET_REWARD_SELECTOR = 0x7050ccd9;

    ICreditFacade public creditFacade;
    ICreditManagerV2 public creditManager;

    address public curveAdapter;
    address public convexAdapter;
    address public primaryToken;
    address public depositToken;

    bool public parametersSet;
    IGearboxVault public admin;

    function setParameters(
        ICreditFacade creditFacade_,
        ICreditManagerV2 creditManager_,
        address curveAdapter_,
        address convexAdapter_,
        address primaryToken_,
        address depositToken_
    ) external {
        require(!parametersSet, ExceptionsLibrary.FORBIDDEN);
        creditFacade = creditFacade_;
        creditManager = creditManager_;
        curveAdapter = curveAdapter_;
        convexAdapter = convexAdapter_;
        primaryToken = primaryToken_;
        depositToken = depositToken_;

        parametersSet = true;
        admin = IGearboxVault(msg.sender);
    }

    function verifyInstances()
        external
        view
        returns (
            int128 primaryIndex,
            address convexOutputToken,
            uint256 poolId
        )
    {
        ICurveV1Adapter curveAdapter_ = ICurveV1Adapter(curveAdapter);
        IConvexV1BaseRewardPoolAdapter convexAdapter_ = IConvexV1BaseRewardPoolAdapter(convexAdapter);

        poolId = convexAdapter_.pid();

        require(creditFacade.isTokenAllowed(primaryToken), ExceptionsLibrary.INVALID_TOKEN);

        bool havePrimaryTokenInCurve = false;

        for (uint256 i = 0; i < curveAdapter_.nCoins(); ++i) {
            address tokenI = curveAdapter_.coins(i);
            if (tokenI == primaryToken) {
                primaryIndex = int128(int256(i));
                havePrimaryTokenInCurve = true;
            }
        }

        require(havePrimaryTokenInCurve, ExceptionsLibrary.INVALID_TOKEN);

        address lpToken = curveAdapter_.lp_token();
        convexOutputToken = address(convexAdapter_.stakedPhantomToken());
        require(lpToken == convexAdapter_.curveLPtoken(), ExceptionsLibrary.INVALID_TARGET);
    }

    function calculateEarnedCvxAmountByEarnedCrvAmount(uint256 crvAmount, address cvxTokenAddress)
        public
        view
        returns (uint256)
    {
        IConvexToken cvxToken = IConvexToken(cvxTokenAddress);

        unchecked {
            uint256 supply = cvxToken.totalSupply();

            uint256 cliff = supply / cvxToken.reductionPerCliff();
            uint256 totalCliffs = cvxToken.totalCliffs();

            if (cliff < totalCliffs) {
                uint256 reduction = totalCliffs - cliff;
                uint256 cvxAmount = FullMath.mulDiv(crvAmount, reduction, totalCliffs);

                uint256 amtTillMax = cvxToken.maxSupply() - supply;
                if (cvxAmount > amtTillMax) {
                    cvxAmount = amtTillMax;
                }

                return cvxAmount;
            }

            return 0;
        }
    }

    function calculateClaimableRewards(address creditAccount, address vaultGovernance) public view returns (uint256) {
        if (creditAccount == address(0)) {
            return 0;
        }

        uint256 earnedCrvAmount = IConvexV1BaseRewardPoolAdapter(convexAdapter).earned(creditAccount);
        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();

        uint256 valueCrvToUsd = oracle.convertToUSD(earnedCrvAmount, protocolParams.crv);
        uint256 valueCvxToUsd = oracle.convertToUSD(
            calculateEarnedCvxAmountByEarnedCrvAmount(earnedCrvAmount, protocolParams.cvx),
            protocolParams.cvx
        );

        return oracle.convertFromUSD(valueCrvToUsd + valueCvxToUsd, primaryToken);
    }

    function calculateDesiredTotalValue(
        address creditAccount,
        address vaultGovernance,
        uint256 marginalFactorD9
    ) external view returns (uint256 expectedAllAssetsValue, uint256 currentAllAssetsValue) {
        (currentAllAssetsValue, ) = creditFacade.calcTotalValue(creditAccount);
        currentAllAssetsValue += calculateClaimableRewards(creditAccount, vaultGovernance);

        (, , uint256 borrowAmountWithInterestAndFees) = creditManager.calcCreditAccountAccruedInterest(creditAccount);

        uint256 currentTvl = currentAllAssetsValue - borrowAmountWithInterestAndFees;
        expectedAllAssetsValue = FullMath.mulDiv(currentTvl, marginalFactorD9, D9);
    }

    function calcConvexTokensToWithdraw(
        uint256 desiredValueNominatedUnderlying,
        address creditAccount,
        address convexOutputToken
    ) public view returns (uint256) {
        uint256 currentConvexTokensAmount = IERC20(convexOutputToken).balanceOf(creditAccount);

        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());
        uint256 valueInConvexNominatedUnderlying = oracle.convert(
            currentConvexTokensAmount,
            convexOutputToken,
            primaryToken
        );

        if (desiredValueNominatedUnderlying >= valueInConvexNominatedUnderlying) {
            return currentConvexTokensAmount;
        }

        return
            FullMath.mulDiv(
                currentConvexTokensAmount,
                desiredValueNominatedUnderlying,
                valueInConvexNominatedUnderlying
            );
    }

    function calcRateRAY(address tokenFrom, address tokenTo) public view returns (uint256) {
        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());
        return oracle.convert(D27, tokenFrom, tokenTo);
    }

    function calculateAmountInMaximum(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 minSlippageD9
    ) public view returns (uint256) {
        uint256 rateRAY = calcRateRAY(toToken, fromToken);
        uint256 amountInExpected = FullMath.mulDiv(amount, rateRAY, D27) + 1;
        return FullMath.mulDiv(amountInExpected, D9 + minSlippageD9, D9) + 1;
    }

    function createUniswapMulticall(
        address tokenFrom,
        address tokenTo,
        uint256 fee,
        address adapter,
        uint256 slippage
    ) public view returns (MultiCall memory) {
        uint256 rateRAY = calcRateRAY(tokenFrom, tokenTo);

        IUniswapV3Adapter.ExactAllInputParams memory params = IUniswapV3Adapter.ExactAllInputParams({
            path: abi.encodePacked(tokenFrom, uint24(fee), tokenTo),
            deadline: block.timestamp + 900,
            rateMinRAY: FullMath.mulDiv(rateRAY, D9 - slippage, D9)
        });

        return
            MultiCall({
                target: adapter,
                callData: abi.encodeWithSelector(IUniswapV3Adapter.exactAllInput.selector, params)
            });
    }

    function checkNecessaryDepositExchange(
        uint256 expectedMaximalDepositTokenValueNominatedUnderlying,
        address vaultGovernance,
        address creditAccount
    ) public {
        address depositToken_ = depositToken;
        address primaryToken_ = primaryToken;

        if (depositToken_ == primaryToken_) {
            return;
        }

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();

        IGearboxVaultGovernance.OperatorParams memory operatorParams = IGearboxVaultGovernance(vaultGovernance)
            .operatorParams();

        uint256 currentDepositTokenAmount = IERC20(depositToken_).balanceOf(creditAccount);
        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());

        uint256 currentValueDepositTokenNominatedUnderlying = oracle.convert(
            currentDepositTokenAmount,
            depositToken_,
            primaryToken_
        );

        if (currentValueDepositTokenNominatedUnderlying > expectedMaximalDepositTokenValueNominatedUnderlying) {
            uint256 toSwap = FullMath.mulDiv(
                currentDepositTokenAmount,
                currentValueDepositTokenNominatedUnderlying - expectedMaximalDepositTokenValueNominatedUnderlying,
                currentValueDepositTokenNominatedUnderlying
            );
            MultiCall[] memory calls = new MultiCall[](1);

            uint256 expectedOutput = oracle.convert(toSwap, depositToken_, primaryToken_);

            ISwapRouter.ExactInputParams memory inputParams = ISwapRouter.ExactInputParams({
                path: abi.encodePacked(depositToken_, operatorParams.largePoolFeeUsed, primaryToken_),
                recipient: creditAccount,
                deadline: block.timestamp + 900,
                amountIn: toSwap,
                amountOutMinimum: FullMath.mulDiv(expectedOutput, D9 - protocolParams.minSlippageD9, D9)
            });

            calls[0] = MultiCall({ // swap deposit to primary token
                target: protocolParams.univ3Adapter,
                callData: abi.encodeWithSelector(ISwapRouter.exactInput.selector, inputParams)
            });

            admin.multicall(calls);
        }
    }

    function claimRewards(address vaultGovernance, address creditAccount) public {
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();

        IGearboxVaultGovernance.OperatorParams memory operatorParams = IGearboxVaultGovernance(vaultGovernance)
            .operatorParams();

        MultiCall[] memory calls = new MultiCall[](1);

        address weth = creditManager.wethAddress();

        calls[0] = MultiCall({ // taking crv and cvx
            target: convexAdapter,
            callData: abi.encodeWithSelector(GET_REWARD_SELECTOR, creditAccount, true)
        });

        admin.multicall(calls);

        calls = new MultiCall[](3);

        calls[0] = createUniswapMulticall(
            protocolParams.crv,
            weth,
            10000,
            protocolParams.univ3Adapter,
            protocolParams.minSmallPoolsSlippageD9
        );
        calls[1] = createUniswapMulticall(
            protocolParams.cvx,
            weth,
            10000,
            protocolParams.univ3Adapter,
            protocolParams.minSmallPoolsSlippageD9
        );
        calls[2] = createUniswapMulticall(
            weth,
            primaryToken,
            operatorParams.largePoolFeeUsed,
            protocolParams.univ3Adapter,
            protocolParams.minSlippageD9
        );

        admin.multicall(calls);
    }

    function withdrawFromConvex(
        uint256 amount,
        address vaultGovernance,
        uint256 poolId,
        int128 primaryIndex
    ) public {
        if (amount == 0) {
            return;
        }

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();

        address curveLpToken = ICurveV1Adapter(curveAdapter).lp_token();
        uint256 rateRAY = calcRateRAY(curveLpToken, primaryToken);

        MultiCall[] memory calls = new MultiCall[](3);

        calls[0] = MultiCall({
            target: convexAdapter,
            callData: abi.encodeWithSelector(IBaseRewardPool.withdraw.selector, amount, false)
        });

        calls[1] = MultiCall({
            target: creditManager.contractToAdapter(IConvexV1BaseRewardPoolAdapter(convexAdapter).operator()),
            callData: abi.encodeWithSelector(IBooster.withdrawAll.selector, poolId)
        });

        calls[2] = MultiCall({
            target: curveAdapter,
            callData: abi.encodeWithSelector(
                ICurveV1Adapter.remove_all_liquidity_one_coin.selector,
                primaryIndex,
                FullMath.mulDiv(rateRAY, D9 - protocolParams.minCurveSlippageD9, D9)
            )
        });

        admin.multicall(calls);
    }

    function depositToConvex(
        MultiCall memory debtManagementCall,
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams,
        uint256 poolId,
        int128 primaryIndex
    ) public {
        MultiCall[] memory calls = new MultiCall[](3);

        address curveLpToken = ICurveV1Adapter(curveAdapter).lp_token();
        uint256 rateRAY = calcRateRAY(primaryToken, curveLpToken);

        calls[0] = debtManagementCall;

        calls[1] = MultiCall({
            target: curveAdapter,
            callData: abi.encodeWithSelector(
                ICurveV1Adapter.add_all_liquidity_one_coin.selector,
                primaryIndex,
                FullMath.mulDiv(rateRAY, D9 - protocolParams.minCurveSlippageD9, D9)
            )
        });

        calls[2] = MultiCall({
            target: creditManager.contractToAdapter(IConvexV1BaseRewardPoolAdapter(convexAdapter).operator()),
            callData: abi.encodeWithSelector(IBooster.depositAll.selector, poolId, true)
        });

        admin.multicall(calls);
    }

    function adjustPosition(uint256 expectedAllAssetsValue, uint256 currentAllAssetsValue, address vaultGovernance, uint256 marginalFactorD9, int128 primaryIndex, uint256 poolId, address convexOutputToken) external {

        address creditAccount_ = getCreditAccount();
        claimRewards(vaultGovernance, creditAccount_);

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance).delayedProtocolParams();
        ICreditFacade creditFacade_ = creditFacade;

        checkNecessaryDepositExchange(
            FullMath.mulDiv(expectedAllAssetsValue, D9, marginalFactorD9),
            vaultGovernance,
            creditAccount_
        );

        uint256 currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(creditAccount_);

        if (expectedAllAssetsValue >= currentAllAssetsValue) {
            uint256 delta = expectedAllAssetsValue - currentAllAssetsValue;

            MultiCall memory increaseDebtCall = MultiCall({
                target: address(creditFacade_),
                callData: abi.encodeWithSelector(ICreditFacade.increaseDebt.selector, delta)
            });

            depositToConvex(increaseDebtCall, protocolParams, poolId, primaryIndex);
        } else {
            uint256 delta = currentAllAssetsValue - expectedAllAssetsValue;

            if (currentPrimaryTokenAmount >= delta) {
                MultiCall memory decreaseDebtCall = MultiCall({
                    target: address(creditFacade_),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });

                depositToConvex(decreaseDebtCall, protocolParams, poolId, primaryIndex);
            } else {
                uint256 convexAmountToWithdraw = calcConvexTokensToWithdraw(
                    delta - currentPrimaryTokenAmount,
                    creditAccount_,
                    convexOutputToken
                );
                withdrawFromConvex(convexAmountToWithdraw, vaultGovernance, poolId, primaryIndex);

                currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(creditAccount_);
                if (currentPrimaryTokenAmount < delta) {
                    delta = currentPrimaryTokenAmount;
                }

                MultiCall[] memory decreaseCall = new MultiCall[](1);
                decreaseCall[0] = MultiCall({
                    target: address(creditFacade_),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });

                admin.multicall(decreaseCall);
            }
        }

        emit PositionAdjusted(tx.origin, msg.sender, expectedAllAssetsValue);
    }

    function getCreditAccount() public view returns (address) {
        return creditManager.creditAccounts(address(admin));
    }

    function swapExactOutput(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 untouchableSum,
        address vaultGovernance,
        address creditAccount
    ) external {
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();

        IGearboxVaultGovernance.OperatorParams memory operatorParams = IGearboxVaultGovernance(vaultGovernance)
            .operatorParams();

        uint256 allowedToUse = IERC20(fromToken).balanceOf(creditAccount) - untouchableSum;
        uint256 amountInMaximum = calculateAmountInMaximum(fromToken, toToken, amount, protocolParams.minSlippageD9);

        if (amountInMaximum > allowedToUse) {
            amount = FullMath.mulDiv(amount, allowedToUse, amountInMaximum);
            amountInMaximum = allowedToUse;
        }

        ISwapRouter.ExactOutputParams memory uniParams = ISwapRouter.ExactOutputParams({
            path: abi.encodePacked(fromToken, operatorParams.largePoolFeeUsed, toToken),
            recipient: creditAccount,
            deadline: block.timestamp + 900,
            amountOut: amount,
            amountInMaximum: amountInMaximum
        });

        MultiCall[] memory calls = new MultiCall[](1);

        calls[0] = MultiCall({
            target: protocolParams.univ3Adapter,
            callData: abi.encodeWithSelector(ISwapRouter.exactOutput.selector, uniParams)
        });

        admin.multicall(calls);
    }

    function pullFromAddress(uint256 amount, address vaultGovernance)
        external
        returns (uint256[] memory actualAmounts)
    {
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();

        IGearboxVaultGovernance.OperatorParams memory operatorParams = IGearboxVaultGovernance(vaultGovernance)
            .operatorParams();

        address depositToken_ = depositToken;
        address primaryToken_ = primaryToken;

        uint256 depositBalance = IERC20(depositToken_).balanceOf(address(admin));
        uint256 primaryBalance = IERC20(primaryToken_).balanceOf(address(admin));

        if (depositBalance < amount && depositToken_ != primaryToken_ && primaryBalance > 0) {
            uint256 amountInMaximum = calculateAmountInMaximum(
                primaryToken_,
                depositToken_,
                amount - depositBalance,
                protocolParams.minSlippageD9
            );

            uint256 outputWant = amount - depositBalance;

            if (amountInMaximum > primaryBalance) {
                outputWant = FullMath.mulDiv(outputWant, primaryBalance, amountInMaximum);
                amountInMaximum = primaryBalance;
            }

            ISwapRouter router = ISwapRouter(protocolParams.uniswapRouter);
            ISwapRouter.ExactOutputParams memory uniParams = ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(primaryToken_, operatorParams.largePoolFeeUsed, depositToken_),
                recipient: address(admin),
                deadline: block.timestamp + 900,
                amountOut: outputWant,
                amountInMaximum: amountInMaximum
            });
            admin.swap(router, uniParams, primaryToken_, amountInMaximum);
        }

        depositBalance = IERC20(depositToken_).balanceOf(address(admin));
        if (amount > depositBalance) {
            amount = depositBalance;
        }

        actualAmounts = new uint256[](1);
        actualAmounts[0] = amount;
    }

    event PositionAdjusted(address indexed origin, address indexed sender, uint256 newTotalAssetsValue);
}
