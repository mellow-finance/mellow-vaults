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
import "../external/Cvx.sol";
import "forge-std/console2.sol";

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
        uint256 valueUnderlying = _calculateClaimableRewards();
        
        if (primaryToken != depositToken) {
            valueUnderlying += IERC20(primaryToken).balanceOf(address(this));
        }

        if (creditAccount != address(0)) {
            (uint256 total, ) = creditFacade.calcTotalValue(creditAccount);
            (, , uint256 borrowAmountWithInterestAndFees) = creditManager.calcCreditAccountAccruedInterest(
                creditAccount
            );

            if (total >= borrowAmountWithInterestAndFees) {
                valueUnderlying += total - borrowAmountWithInterestAndFees;
            }
        }

        minTokenAmounts = new uint256[](1);

        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());
        uint256 valueDeposit = oracle.convert(valueUnderlying, primaryToken, depositToken) +
            IERC20(depositToken).balanceOf(address(this));

        minTokenAmounts[0] = valueDeposit;
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
        (, uint256 total, uint256 previousTotal) = _calculateDesiredTotalValue();
        _adjustPosition(total, previousTotal);
    }

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory)
    {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);

        if (creditAccount == address(0)) {
            return tokenAmounts;
        }

        address[] memory newCollaterals = new address[](1);
        newCollaterals[0] = depositToken;

        _addAllTokensAsCollateral(newCollaterals);
        return tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        require(creditAccount != address(0), ExceptionsLibrary.INVARIANT);
        uint256 amount = tokenAmounts[0];

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        (uint256 realValue, , uint256 previousTotal) = _calculateDesiredTotalValue();

        _claimRewards();
        _withdrawFromConvex(IERC20(convexOutputToken).balanceOf(creditAccount));

        (, , uint256 debtAmount) = creditManager.calcCreditAccountAccruedInterest(creditAccount);
        uint256 underlyingBalance = IERC20(primaryToken).balanceOf(creditAccount);
        if (underlyingBalance < debtAmount + 1) {
            _swapExactOutput(depositToken, primaryToken, debtAmount + 1 - underlyingBalance, 0);
        }

        uint256 depositBalance = IERC20(depositToken).balanceOf(creditAccount);
        if (depositBalance < amount && primaryToken != depositToken) {
            _swapExactOutput(primaryToken, depositToken, amount - depositBalance, debtAmount + 1);
        }

        MultiCall[] memory noCalls = new MultiCall[](0);
        creditFacade.closeCreditAccount(address(this), 0, false, noCalls);

        uint256 finalDepositBalance = IERC20(depositToken).balanceOf(address(this));
        if (finalDepositBalance < amount) {
            amount = finalDepositBalance;
        }

        creditAccount = address(0);

        IERC20(depositToken).safeTransfer(to, amount);
        actualTokenAmounts = new uint256[](1);

        actualTokenAmounts[0] = amount;
        
    }

    function _openCreditAccount() internal {

        require(creditAccount == address(0), ExceptionsLibrary.DUPLICATE);

        ICreditFacade creditFacade_ = creditFacade;

        (uint256 minLimit, ) = creditFacade_.limits();
        uint256 balance = IERC20(primaryToken).balanceOf(address(this));

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        if (depositToken != primaryToken && balance < minLimit) {
            ISwapRouter router = ISwapRouter(protocolParams.uniswapRouter);
            uint256 amountInMaximum = _calculateAmountInMaximum(depositToken, primaryToken, minLimit - balance, protocolParams.minSlippageD9);
            require(IERC20(depositToken).balanceOf(address(this)) >= amountInMaximum, ExceptionsLibrary.INVARIANT);

            ISwapRouter.ExactOutputParams memory uniParams = ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(depositToken, uint24(500), primaryToken),
                recipient: address(this),
                deadline: block.timestamp + 900,
                amountOut: minLimit - balance,
                amountInMaximum: amountInMaximum
            });
            router.exactOutput(uniParams);

            balance = IERC20(primaryToken).balanceOf(address(this));
        }

        require(balance >= minLimit, ExceptionsLibrary.LIMIT_UNDERFLOW);

        IERC20(primaryToken).safeIncreaseAllowance(address(creditManager), balance);
        creditFacade_.openCreditAccount(
            balance,
            address(this),
            uint16((marginalFactorD9 - D9) / D7),
            protocolParams.referralCode
        );
        IERC20(primaryToken).approve(address(creditManager), 0);

        creditAccount = creditManager.getCreditAccountOrRevert(address(this));
        creditFacade_.enableToken(depositToken);
        
        address[] memory newCollaterals = new address[](2);
        newCollaterals[0] = depositToken;
        newCollaterals[1] = primaryToken;

        _addAllTokensAsCollateral(newCollaterals);
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

        (, , uint256 allAssetsValue) = _calculateDesiredTotalValue();
        marginalFactorD9 = marginalFactorD9_;
        (, uint256 realValueWithMargin, ) = _calculateDesiredTotalValue();

        _adjustPosition(realValueWithMargin, allAssetsValue);
    }

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    function _swapExactOutput(address fromToken, address toToken, uint256 amount, uint256 untouchableSum) internal {

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

    function _calculateAmountInMaximum(address fromToken, address toToken, uint256 amount, uint256 minSlippageD9) internal returns (uint256) {
        uint256 rateRAY = _calcRateRAY(toToken, fromToken);
        uint256 amountInExpected = FullMath.mulDiv(amount, rateRAY, D27);
        return FullMath.mulDiv(amountInExpected, D9 + minSlippageD9, D9);
    }

    function _addAllTokensAsCollateral(address[] memory tokens) internal {

        ICreditFacade creditFacade_ = creditFacade;
        MultiCall[] memory calls = new MultiCall[](tokens.length);
        address creditManagerAddress = address(creditManager);

        for (uint256 i = 0; i < tokens.length; ++i) {

            address token = tokens[i];
            uint256 amount = IERC20(token).balanceOf(address(this));

            IERC20(token).safeIncreaseAllowance(creditManagerAddress, amount);

            calls[i] = MultiCall({
                target: address(creditFacade_),
                callData: abi.encodeWithSelector(ICreditFacade.addCollateral.selector, address(this), token, amount)
            });
        }

        creditFacade_.multicall(calls);

        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            IERC20(token).approve(creditManagerAddress, 0);
        }
    }

    function _adjustPosition(
        uint256 underlyingWant,
        uint256 underlyingCurrent    
    ) internal {

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();
        ICreditFacade creditFacade_ = creditFacade;

        _checkDepositExchange(underlyingWant);
        uint256 currentAmount = IERC20(primaryToken).balanceOf(creditAccount);

        address lp_token = ICurveV1Adapter(curveAdapter).lp_token();
        uint256 rateRAY = _calcRateRAY(primaryToken, lp_token);

        if (underlyingWant >= underlyingCurrent) {
            uint256 delta = underlyingWant - underlyingCurrent;
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
            uint256 delta = underlyingCurrent - underlyingWant;

            if (currentAmount < delta) {
                _claimRewards();
                currentAmount = IERC20(primaryToken).balanceOf(creditAccount);
            }

            if (currentAmount >= delta) {
                MultiCall[] memory calls = new MultiCall[](1);
                calls[0] = MultiCall({
                    target: address(creditFacade_),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });
                creditFacade.multicall(calls);
            } else {
                uint256 convexToOutput = _calcConvexTokensToOutput(delta - currentAmount);
                _withdrawFromConvex(convexToOutput);
                
                uint256 currentBalance = IERC20(primaryToken).balanceOf(creditAccount);
                if (currentBalance < delta) {
                    delta = currentBalance;
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

        address lp_token = ICurveV1Adapter(curveAdapter).lp_token();
        uint256 rateRAY = _calcRateRAY(lp_token, primaryToken);

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

    function _checkDepositExchange(uint256 underlyingWant) internal {
        if (depositToken == primaryToken) {
            return;
        }

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        uint256 amount = IERC20(depositToken).balanceOf(creditAccount);
        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());

        uint256 valueDepositTokenToUnderlying = oracle.convert(amount, depositToken, primaryToken);

        if (valueDepositTokenToUnderlying >= underlyingWant) {
            uint256 toSwap = FullMath.mulDiv(
                amount,
                underlyingWant,
                valueDepositTokenToUnderlying
            );
            MultiCall[] memory calls = new MultiCall[](0);

            uint256 finalAmount = oracle.convert(toSwap, depositToken, primaryToken);

            ISwapRouter.ExactInputParams memory inputParams = ISwapRouter.ExactInputParams({
                path: abi.encodePacked(depositToken, uint24(500), primaryToken),
                recipient: creditAccount,
                deadline: block.timestamp + 900,
                amountIn: toSwap,
                amountOutMinimum: FullMath.mulDiv(finalAmount, D9 - protocolParams.minSlippageD9, D9)
            });

            calls[0] = MultiCall({ // swap deposit to primary token
                target: protocolParams.univ3Adapter,
                callData: abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, inputParams)
            });

            creditFacade.multicall(calls);
        }
    }

    function _createUniswapMulticall(
        address tokenFrom,
        address tokenTo,
        uint256 fee,
        address adapter
    ) internal view returns (MultiCall memory) {
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();
        uint256 rateRAY = _calcRateRAY(tokenFrom, tokenTo);

        IUniswapV3Adapter.ExactAllInputParams memory params = IUniswapV3Adapter.ExactAllInputParams({
            path: abi.encodePacked(tokenFrom, uint24(fee), tokenTo),
            deadline: block.timestamp + 900,
            rateMinRAY: FullMath.mulDiv(rateRAY, D9 - protocolParams.minSlippageD9, D9)
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

        calls[0] = _createUniswapMulticall(protocolParams.crv, weth, 10000, protocolParams.univ3Adapter);
        calls[1] = _createUniswapMulticall(protocolParams.cvx, weth, 10000, protocolParams.univ3Adapter);
        calls[2] = _createUniswapMulticall(weth, primaryToken, 500, protocolParams.univ3Adapter);

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
            uint256 realValue,
            uint256 realValueWithMargin,
            uint256 allAssetsValue
        )
    {
        (allAssetsValue, ) = creditFacade.calcTotalValue(creditAccount);
        (, , uint256 borrowAmountWithInterestAndFees) = creditManager.calcCreditAccountAccruedInterest(creditAccount);
        realValue = allAssetsValue - borrowAmountWithInterestAndFees + _calculateClaimableRewards();
        realValueWithMargin = FullMath.mulDiv(realValue, marginalFactorD9, D9);
    }

    function _calcConvexTokensToOutput(uint256 underlyingAmount) internal view returns (uint256) {
        uint256 amount = IERC20(convexOutputToken).balanceOf(creditAccount);

        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());
        uint256 valueConvexToUnderlying = oracle.convert(amount, convexOutputToken, primaryToken);

        if (underlyingAmount >= valueConvexToUnderlying) {
            return amount;
        }

        return FullMath.mulDiv(amount, underlyingAmount, valueConvexToUnderlying);
    }

    function _calculateClaimableRewards() internal view returns (uint256) {
        uint256 amount = IConvexV1BaseRewardPoolAdapter(convexAdapter).earned(creditAccount);
        IPriceOracleV2 oracle = IPriceOracleV2(creditManager.priceOracle());

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        uint256 valueCrvToUsd = oracle.convertToUSD(amount, protocolParams.crv);
        uint256 valueCvxToUsd = oracle.convertToUSD(_calculateCvxByCrv(amount, protocolParams.cvx), protocolParams.cvx);

        return oracle.convertFromUSD(valueCrvToUsd + valueCvxToUsd, primaryToken);
    }

    function _calculateCvxByCrv(uint256 crvAmount, address cvx) internal view returns (uint256) {
        ConvexToken cvxToken = ConvexToken(cvx);

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