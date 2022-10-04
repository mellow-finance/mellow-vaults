// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "./IntegrationVault.sol";
import "../interfaces/external/gearbox/ICreditFacade.sol";
import "../interfaces/external/gearbox/helpers/ICreditManagerV2.sol";
import "../interfaces/external/gearbox/helpers/IPriceOracle.sol";
import "../interfaces/external/gearbox/helpers/convex/IBooster.sol";
import "../interfaces/external/gearbox/helpers/convex/IBaseRewardPool.sol";
import "../interfaces/external/gearbox/ICurveV1Adapter.sol";
import "../interfaces/external/gearbox/IUniversalAdapter.sol";
import "../interfaces/external/gearbox/IUniswapV3Adapter.sol";
import "../interfaces/external/gearbox/IConvexV1BaseRewardPoolAdapter.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IGearboxVault.sol";
import "../interfaces/vaults/IGearboxVaultGovernance.sol";
import "../interfaces/external/convex/ICvx.sol";

contract GearboxVault is IGearboxVault, IntegrationVault {
    using SafeERC20 for IERC20;

    uint256 public constant D9 = 10**9;
    uint256 public constant D27 = 10**27;
    uint256 public constant D18 = 10**18;
    uint256 public constant D7 = 10**7;
    bytes4 public constant GET_REWARD_SELECTOR = 0x7050ccd9;

    ICreditFacade public creditFacade;
    ICreditManagerV2 public creditManager;

    address public creditAccount;

    address public primaryToken;
    address public depositToken;
    address public curveAdapter;
    address public convexAdapter;
    int128 primaryIndex;
    uint256 poolId;
    address convexOutputToken;

    uint256 marginalFactorD9;

    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        uint256 primaryTokenAmount = _calculateClaimableRewards();

        if (primaryToken != depositToken) {
            primaryTokenAmount += IERC20(primaryToken).balanceOf(address(this));
        }

        if (creditAccount != address(0)) {
            (uint256 currentAllAssetsValue, ) = creditFacade.calcTotalValue(creditAccount);
            (, , uint256 borrowAmountWithInterestAndFees) = creditManager.calcCreditAccountAccruedInterest(
                creditAccount
            );

            if (currentAllAssetsValue >= borrowAmountWithInterestAndFees) {
                primaryTokenAmount += currentAllAssetsValue - borrowAmountWithInterestAndFees;
            }
        }

        minTokenAmounts = new uint256[](1);

        if (primaryToken == depositToken) {
            minTokenAmounts[0] = primaryTokenAmount + IERC20(depositToken).balanceOf(address(this));
        }
        else {
            IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());
            uint256 valueDeposit = oracle.convert(primaryTokenAmount, primaryToken, depositToken) +
                IERC20(depositToken).balanceOf(address(this));

            minTokenAmounts[0] = valueDeposit;
        }

        maxTokenAmounts = minTokenAmounts;
    }

    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        require(vaultTokens_.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        _initialize(vaultTokens_, nft_);

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory params = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolPerVaultParams(nft_);
        primaryToken = params.primaryToken;
        depositToken = vaultTokens_[0];
        curveAdapter = params.curveAdapter;
        convexAdapter = params.convexAdapter;
        marginalFactorD9 = params.initialMarginalValueD9;

        creditFacade = ICreditFacade(params.facade);
        creditManager = ICreditManagerV2(creditFacade.creditManager());

        _verifyInstances(primaryToken);
    }

    function openCreditAccount() external {
        _openCreditAccount();
    }

    function adjustPosition() external {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        (uint256 expectedAllAssetsValue, uint256 currentAllAssetsValue) = _calculateDesiredTotalValue();
        _adjustPosition(expectedAllAssetsValue, currentAllAssetsValue);
    }

    function _push(uint256[] memory tokenAmounts, bytes memory) internal override returns (uint256[] memory) {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);

        if (creditAccount != address(0)) {
            _addDepositTokenAsCollateral();
        }

        return tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        require(creditAccount != address(0), ExceptionsLibrary.INVARIANT);
        uint256 amountToPull = tokenAmounts[0];

        _claimRewards();
        _withdrawFromConvex(IERC20(convexOutputToken).balanceOf(creditAccount));

        (, , uint256 debtAmount) = creditManager.calcCreditAccountAccruedInterest(creditAccount);
        uint256 underlyingBalance = IERC20(primaryToken).balanceOf(creditAccount);
        if (underlyingBalance < debtAmount + 1) {
            _swapExactOutput(depositToken, primaryToken, debtAmount + 1 - underlyingBalance, 0);
        }

        uint256 depositTokenBalance = IERC20(depositToken).balanceOf(creditAccount);
        if (depositTokenBalance < amountToPull && primaryToken != depositToken) {
            _swapExactOutput(primaryToken, depositToken, amountToPull - depositTokenBalance, debtAmount + 1);
        }

        MultiCall[] memory noCalls = new MultiCall[](0);
        creditFacade.closeCreditAccount(address(this), 0, false, noCalls);

        depositTokenBalance = IERC20(depositToken).balanceOf(address(this));
        if (depositTokenBalance < amountToPull) {
            amountToPull = depositTokenBalance;
        }

        creditAccount = address(0);

        IERC20(depositToken).safeTransfer(to, amountToPull);
        actualTokenAmounts = new uint256[](1);

        actualTokenAmounts[0] = amountToPull;
    }

    function _openCreditAccount() internal {
        require(creditAccount == address(0), ExceptionsLibrary.DUPLICATE);

        ICreditFacade creditFacade_ = creditFacade;

        (uint256 minBorrowingLimit, ) = creditFacade_.limits();
        uint256 currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(address(this));

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        if (depositToken != primaryToken && currentPrimaryTokenAmount < minBorrowingLimit) {
            ISwapRouter router = ISwapRouter(protocolParams.uniswapRouter);
            uint256 amountInMaximum = _calculateAmountInMaximum(
                depositToken,
                primaryToken,
                minBorrowingLimit - currentPrimaryTokenAmount,
                protocolParams.minSlippageD9
            );
            require(IERC20(depositToken).balanceOf(address(this)) >= amountInMaximum, ExceptionsLibrary.INVARIANT);

            ISwapRouter.ExactOutputParams memory uniParams = ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(depositToken, uint24(500), primaryToken),
                recipient: address(this),
                deadline: block.timestamp + 900,
                amountOut: minBorrowingLimit - currentPrimaryTokenAmount,
                amountInMaximum: amountInMaximum
            });
            router.exactOutput(uniParams);

            currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(address(this));
        }

        require(currentPrimaryTokenAmount >= minBorrowingLimit, ExceptionsLibrary.LIMIT_UNDERFLOW);

        IERC20(primaryToken).safeIncreaseAllowance(address(creditManager), currentPrimaryTokenAmount);
        creditFacade_.openCreditAccount(
            currentPrimaryTokenAmount,
            address(this),
            uint16((marginalFactorD9 - D9) / D7),
            protocolParams.referralCode
        );
        IERC20(primaryToken).approve(address(creditManager), 0);

        creditAccount = creditManager.getCreditAccountOrRevert(address(this));

        if (depositToken != primaryToken) {
            creditFacade_.enableToken(depositToken);
            _addDepositTokenAsCollateral();
        }
    }

    function _verifyInstances(address primaryToken_) internal {
        ICreditFacade creditFacade_ = creditFacade;
        ICurveV1Adapter curveAdapter_ = ICurveV1Adapter(curveAdapter);
        IConvexV1BaseRewardPoolAdapter convexAdapter_ = IConvexV1BaseRewardPoolAdapter(convexAdapter);

        poolId = convexAdapter_.pid();

        require(creditFacade_.isTokenAllowed(primaryToken_), ExceptionsLibrary.INVALID_TOKEN);

        bool havePrimaryTokenInCurve = false;

        for (uint256 i = 0; i < 4; ++i) {
            address tokenI = curveAdapter_.coins(i);
            if (tokenI == primaryToken_) {
                primaryIndex = int128(int256(i));
                havePrimaryTokenInCurve = true;
            }
        }

        require(havePrimaryTokenInCurve, ExceptionsLibrary.INVALID_TOKEN);

        address lpToken = curveAdapter_.lp_token();
        convexOutputToken = address(convexAdapter_.stakedPhantomToken());
        require(lpToken == convexAdapter_.curveLPtoken(), ExceptionsLibrary.INVALID_TARGET);
    }

    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(IGearboxVault).interfaceId;
    }

    function updateTargetMarginalFactor(uint256 marginalFactorD9_) external {
        require(_isApprovedOrOwner(msg.sender));
        require(marginalFactorD9_ >= D9, ExceptionsLibrary.INVALID_VALUE);

        if (creditAccount == address(0)) {
            marginalFactorD9 = marginalFactorD9_;
            return;
        }

        (, uint256 currentAllAssetsValue) = _calculateDesiredTotalValue();
        marginalFactorD9 = marginalFactorD9_;
        (uint256 expectedAllAssetsValue, ) = _calculateDesiredTotalValue();

        _adjustPosition(expectedAllAssetsValue, currentAllAssetsValue);
    }

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    function _swapExactOutput(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 untouchableSum
    ) internal {
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        uint256 allowedToUse = IERC20(fromToken).balanceOf(creditAccount) - untouchableSum;
        uint256 amountInMaximum = _calculateAmountInMaximum(fromToken, toToken, amount, protocolParams.minSlippageD9);

        if (amountInMaximum > allowedToUse) {
            amount = FullMath.mulDiv(amount, allowedToUse, amountInMaximum);
            amountInMaximum = allowedToUse;
        }

        ISwapRouter.ExactOutputParams memory uniParams = ISwapRouter.ExactOutputParams({
            path: abi.encodePacked(fromToken, uint24(500), toToken),
            recipient: creditAccount,
            deadline: block.timestamp + 900,
            amountOut: amount,
            amountInMaximum: amountInMaximum
        });

        { //////////// USE THIS ONLY IN TESTING MODE!!! REMOVE IN PROD
            ISwapRouter router = ISwapRouter(protocolParams.uniswapRouter);
            router.exactOutput(uniParams);
            return;
        }

        MultiCall[] memory calls = new MultiCall[](1);

        calls[0] = MultiCall({
            target: protocolParams.univ3Adapter,
            callData: abi.encodeWithSelector(ISwapRouter.exactOutput.selector, uniParams)
        });

        creditFacade.multicall(calls);
    }

    function _calculateAmountInMaximum(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 minSlippageD9
    ) internal view returns (uint256) {
        uint256 rateRAY = _calcRateRAY(toToken, fromToken);
        uint256 amountInExpected = FullMath.mulDiv(amount, rateRAY, D27) + 1;
        return FullMath.mulDiv(amountInExpected, D9 + minSlippageD9, D9) + 1;
    }

    function _addDepositTokenAsCollateral() internal {

        ICreditFacade creditFacade_ = creditFacade;
        MultiCall[] memory calls = new MultiCall[](1);
        address creditManagerAddress = address(creditManager);

        address token = depositToken;
        uint256 amount = IERC20(token).balanceOf(address(this));

        IERC20(token).safeIncreaseAllowance(creditManagerAddress, amount);

        calls[0] = MultiCall({
            target: address(creditFacade_),
            callData: abi.encodeWithSelector(ICreditFacade.addCollateral.selector, address(this), token, amount)
        });

        creditFacade_.multicall(calls);
        IERC20(token).approve(creditManagerAddress, 0);
    }

    function _adjustPosition(uint256 expectedAllAssetsValue, uint256 currentAllAssetsValue) internal {
        _claimRewards();

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();
        ICreditFacade creditFacade_ = creditFacade;

        _checkNecessaryDepositExchange(FullMath.mulDiv(expectedAllAssetsValue, D9, marginalFactorD9));
        uint256 currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(creditAccount);

        address curveLpToken = ICurveV1Adapter(curveAdapter).lp_token();
        uint256 rateRAY = _calcRateRAY(primaryToken, curveLpToken);

        if (expectedAllAssetsValue >= currentAllAssetsValue) {
            uint256 delta = expectedAllAssetsValue - currentAllAssetsValue;
            MultiCall[] memory calls = new MultiCall[](3);
            calls[0] = MultiCall({
                target: address(creditFacade_),
                callData: abi.encodeWithSelector(ICreditFacade.increaseDebt.selector, delta)
            });

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

            creditFacade.multicall(calls);
        } else {
            uint256 delta = currentAllAssetsValue - expectedAllAssetsValue;

            if (currentPrimaryTokenAmount >= delta) {
                MultiCall[] memory calls = new MultiCall[](1);
                calls[0] = MultiCall({
                    target: address(creditFacade_),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });
                creditFacade.multicall(calls);
            } else {
                uint256 convexAmountToWithdraw = _calcConvexTokensToWithdraw(delta - currentPrimaryTokenAmount);
                _withdrawFromConvex(convexAmountToWithdraw);

                currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(creditAccount);
                if (currentPrimaryTokenAmount < delta) {
                    delta = currentPrimaryTokenAmount;
                }

                MultiCall[] memory decreaseCall = new MultiCall[](1);
                decreaseCall[0] = MultiCall({
                    target: address(creditFacade_),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });

                creditFacade_.multicall(decreaseCall);
            }
        }
    }

    function _withdrawFromConvex(uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        address curveLpToken = ICurveV1Adapter(curveAdapter).lp_token();
        uint256 rateRAY = _calcRateRAY(curveLpToken, primaryToken);

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

        creditFacade.multicall(calls);
    }

    function _checkNecessaryDepositExchange(uint256 expectedMaximalDepositTokenValueNominatedUnderlying) internal {
        if (depositToken == primaryToken) {
            return;
        }

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        uint256 currentDepositTokenAmount = IERC20(depositToken).balanceOf(creditAccount);
        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());

        uint256 currentValueDepositTokenNominatedUnderlying = oracle.convert(currentDepositTokenAmount, depositToken, primaryToken);

        if (currentValueDepositTokenNominatedUnderlying > expectedMaximalDepositTokenValueNominatedUnderlying) {
            uint256 toSwap = FullMath.mulDiv(
                currentDepositTokenAmount,
                currentValueDepositTokenNominatedUnderlying - expectedMaximalDepositTokenValueNominatedUnderlying,
                currentValueDepositTokenNominatedUnderlying
            );
            MultiCall[] memory calls = new MultiCall[](1);

            uint256 expectedOutput = oracle.convert(toSwap, depositToken, primaryToken);

            ISwapRouter.ExactInputParams memory inputParams = ISwapRouter.ExactInputParams({
                path: abi.encodePacked(depositToken, uint24(500), primaryToken),
                recipient: creditAccount,
                deadline: block.timestamp + 900,
                amountIn: toSwap,
                amountOutMinimum: FullMath.mulDiv(expectedOutput, D9 - protocolParams.minSlippageD9, D9)
            });

            calls[0] = MultiCall({ // swap deposit to primary token
                target: protocolParams.univ3Adapter,
                callData: abi.encodeWithSelector(ISwapRouter.exactInput.selector, inputParams)
            });

            { //////////// USE THIS ONLY IN TESTING MODE!!! REMOVE IN PROD
                ISwapRouter router = ISwapRouter(protocolParams.uniswapRouter);
                router.exactInput(inputParams);
                return;
            }

            creditFacade.multicall(calls);
        }
    }

    function _createUniswapMulticall(
        address tokenFrom,
        address tokenTo,
        uint256 fee,
        address adapter,
        uint256 slippage
    ) internal view returns (MultiCall memory) {
        uint256 rateRAY = _calcRateRAY(tokenFrom, tokenTo);

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

    function _claimRewards() internal {
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        MultiCall[] memory calls = new MultiCall[](1);

        address weth = creditManager.wethAddress();

        calls[0] = MultiCall({ // taking crv and cvx
            target: convexAdapter,
            callData: abi.encodeWithSelector(GET_REWARD_SELECTOR, creditAccount, true)
        });

        creditFacade.multicall(calls);

        calls = new MultiCall[](3);

        calls[0] = _createUniswapMulticall(
            protocolParams.crv,
            weth,
            10000,
            protocolParams.univ3Adapter,
            protocolParams.minSmallPoolsSlippageD9
        );
        calls[1] = _createUniswapMulticall(
            protocolParams.cvx,
            weth,
            10000,
            protocolParams.univ3Adapter,
            protocolParams.minSmallPoolsSlippageD9
        );
        calls[2] = _createUniswapMulticall(
            weth,
            primaryToken,
            500,
            protocolParams.univ3Adapter,
            protocolParams.minSlippageD9
        );

        creditFacade.multicall(calls);
    }

    function _calcRateRAY(address tokenFrom, address tokenTo) internal view returns (uint256) {
        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());
        return oracle.convert(D27, tokenFrom, tokenTo);
    }

    function _calculateDesiredTotalValue()
        internal
        view
        returns (
            uint256 expectedAllAssetsValue,
            uint256 currentAllAssetsValue
        )
    {
        (currentAllAssetsValue, ) = creditFacade.calcTotalValue(creditAccount);
        currentAllAssetsValue += _calculateClaimableRewards();

        (, , uint256 borrowAmountWithInterestAndFees) = creditManager.calcCreditAccountAccruedInterest(creditAccount);

        uint256 currentTvl = currentAllAssetsValue - borrowAmountWithInterestAndFees;
        expectedAllAssetsValue = FullMath.mulDiv(currentTvl, marginalFactorD9, D9);
    }

    function _calcConvexTokensToWithdraw(uint256 desiredValueNominatedUnderlying) internal view returns (uint256) {

        uint256 currentConvexTokensAmount = IERC20(convexOutputToken).balanceOf(creditAccount);

        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());
        uint256 valueInConvexNominatedUnderlying = oracle.convert(currentConvexTokensAmount, convexOutputToken, primaryToken);

        if (desiredValueNominatedUnderlying >= valueInConvexNominatedUnderlying) {
            return currentConvexTokensAmount;
        }

        return FullMath.mulDiv(currentConvexTokensAmount, desiredValueNominatedUnderlying, valueInConvexNominatedUnderlying);
    }

    function _calculateClaimableRewards() internal view returns (uint256) {
        if (creditAccount == address(0)) {
            return 0;
        }

        uint256 earnedCrvAmount = IConvexV1BaseRewardPoolAdapter(convexAdapter).earned(creditAccount);
        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        uint256 valueCrvToUsd = oracle.convertToUSD(earnedCrvAmount, protocolParams.crv);
        uint256 valueCvxToUsd = oracle.convertToUSD(_calculateEarnedCvxAmountByEarnedCrvAmount(earnedCrvAmount, protocolParams.cvx), protocolParams.cvx);

        return oracle.convertFromUSD(valueCrvToUsd + valueCvxToUsd, primaryToken);
    }

    function _calculateEarnedCvxAmountByEarnedCrvAmount(uint256 crvAmount, address cvxTokenAddress) internal view returns (uint256) {

        IConvexToken cvxToken = IConvexToken(cvxTokenAddress);

        unchecked {
            uint256 supply = cvxToken.totalSupply();

            uint256 cliff = supply / cvxToken.reductionPerCliff();
            uint256 totalCliffs = cvxToken.totalCliffs();

            if (cliff < totalCliffs) {
                uint256 reduction = totalCliffs - cliff;
                crvAmount = FullMath.mulDiv(crvAmount, reduction, totalCliffs);

                uint256 amtTillMax = cvxToken.maxSupply() - supply;
                if (crvAmount > amtTillMax) {
                    crvAmount = amtTillMax;
                }

                return crvAmount;
            }

            return 0;
        }
    }
}
