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
import "forge-std/console2.sol";

contract GearboxVault is IGearboxVault, IntegrationVault {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 10**9;
    uint256 public constant D27 = 10**27;
    uint256 public constant D18 = 10**27;
    uint256 public constant D7 = 10**7;
    bytes4 public constant GET_REWARD_SELECTOR = 0x7050ccd9;

    ICreditFacade private _creditFacade;
    ICreditManagerV2 private _creditManager;

    address public creditAccount;

    address public primaryToken;
    address public depositToken;
    address public curveAdapter;
    address public convexAdapter;
    int128 primaryIndex;
    uint256 poolId;
    address convexOutputToken;

    uint256 marginalFactorD;

    mapping(address => uint256) public lpTokensToWithdrawOrder;
    mapping(address => uint256) public lastOrderTimestamp;
    uint256 lastWithdrawResetTimestamp;

    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {

        uint256 valueUnderlying = 0;

        if (creditAccount != address(0)) {
            (uint256 total, ) = _creditFacade.calcTotalValue(creditAccount);
            (, , uint256 borrowAmountWithInterestAndFees) = _creditManager.calcCreditAccountAccruedInterest(creditAccount);

            if (total >= borrowAmountWithInterestAndFees) {
                valueUnderlying += total - borrowAmountWithInterestAndFees;
            }
        }

        minTokenAmounts = new uint256[](1);

        IPriceOracleV2 oracle = IPriceOracleV2(_creditManager.priceOracle());
        uint256 valueUsd = oracle.convertToUSD(valueUnderlying, primaryToken);
        uint256 valueDeposit = oracle.convertFromUSD(valueUsd, depositToken) + IERC20(depositToken).balanceOf(address(this));

        minTokenAmounts[0] = valueDeposit;
        maxTokenAmounts = minTokenAmounts;
    }

    function initialize(uint256 nft_, address[] memory vaultTokens_) external {
        require(vaultTokens_.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        _initialize(vaultTokens_, nft_);

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory params = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolPerVaultParams(nft_);
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        primaryToken = params.primaryToken;
        depositToken = vaultTokens_[0];
        curveAdapter = params.curveAdapter;
        convexAdapter = params.convexAdapter;
        marginalFactorD = params.initialMarginalValue;

        _creditFacade = ICreditFacade(params.facade);
        _creditManager = ICreditManagerV2(_creditFacade.creditManager());

        _verifyInstances(primaryToken);
    }

    function adjustPosition() external {
        require(_isApprovedOrOwner(msg.sender), ExceptionsLibrary.FORBIDDEN);
        (, uint256 total, uint256 previousTotal) = _calculateDesiredTotalValue();
        _adjustPosition(total, previousTotal, false);
    }

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        ICreditFacade creditFacade = _creditFacade;

        if (creditAccount == address(0)) {
            _openCreditAccount(creditFacade);
        }

        address token = depositToken;
        uint256 amount = IERC20(token).balanceOf(address(this));

        if (amount > 0) {
            address creditManagerAddress = address(_creditManager);
            IERC20(token).safeIncreaseAllowance(creditManagerAddress, amount);

            MultiCall[] memory calls = new MultiCall[](1);
            calls[0] = MultiCall({
                target: address(creditFacade),
                callData: abi.encodeWithSelector(ICreditFacade.addCollateral.selector, address(this), token, amount)
            });

            creditFacade.multicall(calls);

            IERC20(token).approve(creditManagerAddress, 0);
        }

        actualTokenAmounts = tokenAmounts;
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        uint256 amount = tokenAmounts[0];

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        (uint256 realValue, , uint256 previousTotal) = _calculateDesiredTotalValue();

        _adjustPosition(realValue, previousTotal, true);
        if (primaryToken != depositToken) {

            MultiCall[] memory calls = new MultiCall[](1);

            uint256 amountToSwap = IERC20(primaryToken).balanceOf(creditAccount);
            uint256 rateMinRAY = _calcMinRateRAY(primaryToken, depositToken);

            IUniswapV3Adapter.ExactAllInputParams memory uniParams = IUniswapV3Adapter.ExactAllInputParams({
                path: abi.encodePacked(primaryToken, uint24(500), depositToken),
                deadline: block.timestamp + 900,
                rateMinRAY: rateMinRAY
            });

            calls[0] = MultiCall({
                target: protocolParams.univ3Adapter,
                callData: abi.encodeWithSelector(IUniswapV3Adapter.exactAllInput.selector, uniParams)
            });

            _creditFacade.multicall(calls);
        }

        MultiCall[] memory noCalls = new MultiCall[](0);
        _creditFacade.closeCreditAccount(address(this), 0, false, noCalls);

        uint256 balance = IERC20(depositToken).balanceOf(address(this));
        if (amount > balance) {
            amount = balance;
        }

        IERC20(depositToken).safeTransfer(to, amount);
        actualTokenAmounts = new uint256[](1);

        actualTokenAmounts[0] = amount;
    }

    function _openCreditAccount(ICreditFacade creditFacade) internal {
        (uint256 minLimit, ) = creditFacade.limits();
        uint256 balance = IERC20(primaryToken).balanceOf(address(this));

        require(balance >= minLimit, ExceptionsLibrary.LIMIT_UNDERFLOW);
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        IERC20(primaryToken).safeIncreaseAllowance(address(_creditManager), balance);
        creditFacade.openCreditAccount(balance, address(this), uint16((marginalFactorD - DENOMINATOR) / D7), protocolParams.referralCode);
        IERC20(primaryToken).approve(address(_creditManager), 0);

        creditAccount = _creditManager.getCreditAccountOrRevert(address(this));
        creditFacade.enableToken(depositToken);
    }

    function _verifyInstances(
        address primaryToken_
    ) internal {
        ICreditFacade creditFacade = _creditFacade;
        ICurveV1Adapter curveAdapter_ = ICurveV1Adapter(curveAdapter);
        IConvexV1BaseRewardPoolAdapter convexAdapter_ = IConvexV1BaseRewardPoolAdapter(convexAdapter);

        poolId = convexAdapter_.pid();

        require(creditFacade.isTokenAllowed(primaryToken_), ExceptionsLibrary.INVALID_TOKEN);

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

    function updateTargetMarginalFactor(uint256 marginalFactorD_) external {
        require(_isApprovedOrOwner(msg.sender));
        require(marginalFactorD_ >= DENOMINATOR, ExceptionsLibrary.INVALID_VALUE);

        (, , uint256 allAssetsValue) = _calculateDesiredTotalValue();
        marginalFactorD = marginalFactorD_;
        (, uint256 realValueWithMargin, ) = _calculateDesiredTotalValue();

        _adjustPosition(realValueWithMargin, allAssetsValue, false);
    }

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    function _adjustPosition(
        uint256 underlyingWant,
        uint256 underlyingCurrent,
        bool forceToClose
    ) internal {
        ICreditFacade creditFacade = _creditFacade;

        _checkDepositExchange(underlyingWant);
        uint256 currentAmount = IERC20(primaryToken).balanceOf(creditAccount);

        if (underlyingWant >= underlyingCurrent) {
            uint256 delta = underlyingWant - underlyingCurrent;
            MultiCall[] memory calls = new MultiCall[](3);
            calls[0] = MultiCall({
                target: address(creditFacade),
                callData: abi.encodeWithSelector(ICreditFacade.increaseDebt.selector, delta)
            });

            calls[1] = MultiCall({
                target: curveAdapter,
                callData: abi.encodeWithSelector(
                    ICurveV1Adapter.add_liquidity_one_coin.selector,
                    delta + currentAmount,
                    primaryIndex,
                    0
                )
            });

            calls[2] = MultiCall({
                target: _creditManager.contractToAdapter(IConvexV1BaseRewardPoolAdapter(convexAdapter).operator()),
                callData: abi.encodeWithSelector(IBooster.depositAll.selector, poolId, true)
            });

            creditFacade.multicall(calls);
        } else {
            uint256 delta = underlyingCurrent - underlyingWant;

            if (currentAmount < delta || forceToClose) {
                _claimRewards();
                currentAmount = IERC20(primaryToken).balanceOf(creditAccount);
            }

            if (currentAmount >= delta && !forceToClose) {
                MultiCall[] memory calls = new MultiCall[](1);
                calls[0] = MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });
                creditFacade.multicall(calls);
            } else {
                uint256 convexToOutput = _calcConvexTokensToOutput(delta - currentAmount, forceToClose);

                MultiCall[] memory calls = new MultiCall[](3);
                calls[0] = MultiCall({
                    target: _creditManager.contractToAdapter(IConvexV1BaseRewardPoolAdapter(convexAdapter).operator()),
                    callData: abi.encodeWithSelector(IBooster.withdraw.selector, poolId, convexToOutput)
                });

                calls[1] = MultiCall({
                    target: curveAdapter,
                    callData: abi.encodeWithSelector(
                        ICurveV1Adapter.remove_all_liquidity_one_coin.selector,
                        primaryIndex,
                        0
                    )
                });

                calls[2] = MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });

                creditFacade.multicall(calls);
            }
        }
    }

    function _checkDepositExchange(uint256 underlyingWant) internal {
        if (depositToken == primaryToken) {
            return;
        }

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        uint256 amount = IERC20(depositToken).balanceOf(creditAccount);
        IPriceOracleV2 oracle = IPriceOracleV2(_creditManager.priceOracle());
        uint256 valueDepositTokenToUsd = oracle.convertToUSD(amount, depositToken);
        uint256 valueDepositTokenToUnderlying = oracle.convertFromUSD(valueDepositTokenToUsd, primaryToken);

        if (valueDepositTokenToUnderlying > underlyingWant) {
            uint256 toSwap = FullMath.mulDiv(
                amount,
                valueDepositTokenToUnderlying - underlyingWant,
                valueDepositTokenToUnderlying
            );
            MultiCall[] memory calls = new MultiCall[](0);

            uint256 usdAmount = oracle.convertToUSD(toSwap, depositToken);
            uint256 finalAmount = oracle.convertFromUSD(usdAmount, primaryToken); 

            ISwapRouter.ExactInputParams memory inputParams = ISwapRouter.ExactInputParams({
                path: abi.encodePacked(depositToken, uint24(500), primaryToken),
                recipient: creditAccount,
                deadline: block.timestamp + 900,
                amountIn: toSwap,
                amountOutMinimum: finalAmount
            });

            calls[0] = MultiCall({ // swap deposit to primary token
                target: protocolParams.univ3Adapter,
                callData: abi.encodeWithSelector(
                    ISwapRouter.exactInputSingle.selector,
                    inputParams)
            });

            _creditFacade.multicall(calls);
        }
    }

    function _createUniswapMulticall(address tokenFrom, address tokenTo, uint256 fee, address adapter) internal view returns (MultiCall memory) {

        console2.log("CREATING MULTICALL");

        uint256 rateMinRAY = _calcMinRateRAY(tokenFrom, tokenTo);

        console2.log(rateMinRAY);

        IUniswapV3Adapter.ExactAllInputParams memory params = IUniswapV3Adapter.ExactAllInputParams({
            path: abi.encodePacked(tokenFrom, uint24(fee), tokenTo),
            deadline: block.timestamp + 900,
            rateMinRAY: rateMinRAY
        });

        return MultiCall({
            target: adapter,
            callData: abi.encodeWithSelector(IUniswapV3Adapter.exactAllInput.selector, params)
        });

    }

    function _claimRewards() internal {
        console2.log("CLAIM REWARDS");
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        MultiCall[] memory calls = new MultiCall[](1);

        address weth = _creditManager.wethAddress();

        calls[0] = MultiCall({ // taking crv and cvx
            target: convexAdapter,
            callData: abi.encodeWithSelector(GET_REWARD_SELECTOR, creditAccount, false)
        });

        _creditFacade.multicall(calls);

        console2.log(IERC20(protocolParams.crv).balanceOf(creditAccount));
        console2.log(IERC20(protocolParams.cvx).balanceOf(creditAccount));

        calls = new MultiCall[](3);

        calls[0] = _createUniswapMulticall(protocolParams.crv, weth, 10000, protocolParams.univ3Adapter);
        calls[1] = _createUniswapMulticall(protocolParams.cvx, weth, 10000, protocolParams.univ3Adapter);
        calls[2] = _createUniswapMulticall(weth, primaryToken, 500, protocolParams.univ3Adapter);

        _creditFacade.multicall(calls);

        console2.log("CLAIMED REWARDS");
    }

    function _calcMinRateRAY(address tokenFrom, address tokenTo) internal view returns (uint256) {
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();
        IPriceOracleV2 oracle = IPriceOracleV2(_creditManager.priceOracle());

        uint256 usdAmount = oracle.convertToUSD(D18, tokenFrom);
        uint256 finalAmount = oracle.convertFromUSD(usdAmount, tokenTo); 

        uint256 priceD27 = FullMath.mulDiv(finalAmount, D27, D18);
        uint256 rateMinRAY = FullMath.mulDiv(priceD27, DENOMINATOR - protocolParams.minSlippageD, DENOMINATOR);

        return rateMinRAY;
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
        (allAssetsValue, ) = _creditFacade.calcTotalValue(creditAccount);
        (, , uint256 borrowAmountWithInterestAndFees) = _creditManager.calcCreditAccountAccruedInterest(creditAccount);
        realValue = allAssetsValue - borrowAmountWithInterestAndFees;
        realValueWithMargin = FullMath.mulDiv(realValue, marginalFactorD, DENOMINATOR);
    }

    function _calcConvexTokensToOutput(uint256 underlyingAmount, bool forceToClose) internal view returns (uint256) {
        uint256 amount = IERC20(convexOutputToken).balanceOf(creditAccount);

        if (forceToClose) {
            return amount;
        }

        IPriceOracleV2 oracle = IPriceOracleV2(_creditManager.priceOracle());
        uint256 valueConvexToUsd = oracle.convertToUSD(amount, convexOutputToken);
        uint256 valueConvexToUnderlying = oracle.convertFromUSD(valueConvexToUsd, primaryToken);

        if (underlyingAmount >= valueConvexToUnderlying) {
            return amount;
        }

        return FullMath.mulDiv(amount, underlyingAmount, valueConvexToUnderlying);
    }
}
