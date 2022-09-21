// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "./IntegrationVault.sol";
import "../interfaces/external/gearbox/ICreditFacade.sol";
import "../interfaces/external/gearbox/helpers/ICreditManagerV2.sol";
import "../interfaces/external/gearbox/helpers/IPriceOracle.sol";
import "../interfaces/external/gearbox/helpers/convex/IBooster.sol";
import "../interfaces/external/gearbox/ICurveV1Adapter.sol";
import "../interfaces/external/gearbox/IUniversalAdapter.sol";
import "../interfaces/external/gearbox/IConvexV1BoosterAdapter.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IGearboxVault.sol";
import "../interfaces/vaults/IGearboxVaultGovernance.sol";

contract GearboxVault is IGearboxVault, IntegrationVault {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 10**9;

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

    mapping (address => uint256) public lpTokensToWithdrawOrder;
    mapping (address => uint256) public lastOrderTimestamp;
    uint256 lastWithdrawResetTimestamp;
    


    function tvl() public view override returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        (uint256 total, ) = _creditFacade.calcTotalValue(creditAccount);
        (, , uint256 borrowAmountWithInterestAndFees) = _creditManager.calcCreditAccountAccruedInterest(creditAccount);

        minTokenAmounts = new uint256[](1);
        uint256 valueUnderlying = 0;

        if (total >= borrowAmountWithInterestAndFees) {
            valueUnderlying = total - borrowAmountWithInterestAndFees;
        }

        IPriceOracleV2 oracle = IPriceOracleV2(_creditManager.priceOracle());
        uint256 valueUsd = oracle.convertToUSD(valueUnderlying, primaryToken);
        uint256 valueDeposit = oracle.convertFromUSD(valueUsd, depositToken);

        minTokenAmounts[0] = valueDeposit;
        maxTokenAmounts = minTokenAmounts;
    }

    function initialize(
        uint256 nft_,
        address primaryToken_,
        address depositToken_,
        address curveAdapter_,
        address convexAdapter_,
        address facade_,
        uint256 convexPoolId_,
        uint256 marginalFactorD_,
        bytes memory options
    ) external {
        address[] memory vaultTokens_ = new address[](1);
        vaultTokens_[0] = depositToken_;
        _initialize(vaultTokens_, nft_);

        primaryToken = primaryToken_;
        depositToken = depositToken_;
        curveAdapter = curveAdapter_;
        convexAdapter = convexAdapter_;
        marginalFactorD = marginalFactorD_;
        poolId = convexPoolId_;

        ICreditFacade creditFacade = ICreditFacade(facade_);
        ICreditManagerV2 creditManager = ICreditManagerV2(creditFacade.creditManager());

        _creditFacade = creditFacade;
        _creditManager = creditManager;

        _verifyInstances(convexPoolId_, depositToken_, primaryToken_);
        uint256 amount = _pullExistentials[0];

        uint256 referralCode = 0;
        if (options.length > 0) {
            referralCode = abi.decode(options, (uint256));
        }

        creditFacade.openCreditAccount(amount, address(this), 0, uint16(referralCode));
        creditAccount = creditManager.getCreditAccountOrRevert(address(this));
    }

    function _push(uint256[] memory tokenAmounts, bytes memory)
        internal
        override
        returns (uint256[] memory actualTokenAmounts)
    {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        uint256 amount = tokenAmounts[0];
        if (amount == 0) {
            return new uint256[](1);
        }

        ICreditFacade creditFacade = _creditFacade;

        address token = depositToken;
        address creditFacadeAddress = address(creditFacade);
        IERC20(token).safeIncreaseAllowance(creditFacadeAddress, amount);

        MultiCall[] memory calls = new MultiCall[](1);
        calls[0] = MultiCall({
            target: address(creditFacade),
            callData: abi.encodeWithSelector(ICreditFacade.addCollateral.selector, address(this), token, amount)
        });

        creditFacade.multicall(calls);

        IERC20(token).approve(creditFacadeAddress, 0);
        actualTokenAmounts = tokenAmounts;
        (, uint256 total, uint256 previousTotal) = _calculateDesiredTotalValue();
        _adjustPosition(total, previousTotal, 0);
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        uint256 amount = tokenAmounts[0];
        if (amount == 0) {
            return new uint256[](1);
        }

        uint256 underlyingToPull = amount;
        address depositToken_ = depositToken;
        address primaryToken_ = primaryToken;

        if (depositToken_ != primaryToken_) {
            IPriceOracleV2 oracle = IPriceOracleV2(_creditManager.priceOracle());
            uint256 valueUsd = oracle.convertToUSD(amount, depositToken_);
            underlyingToPull = oracle.convertFromUSD(valueUsd, primaryToken_);
        }

        (
            uint256 realValue,
            uint256 realValueWithMargin,
            uint256 previousValueWithMargin
        ) = _calculateDesiredTotalValue();
        if (underlyingToPull > realValue) {
            underlyingToPull = realValue;
        }

        uint256 underlyingToOutput = 0;
        if (depositToken_ == primaryToken_) {
            underlyingToOutput = underlyingToPull;
        }

        _adjustPosition(
            realValueWithMargin - FullMath.mulDiv(underlyingToPull, marginalFactorD - DENOMINATOR, DENOMINATOR),
            previousValueWithMargin,
            underlyingToOutput
        );
        MultiCall[] memory calls = new MultiCall[](2);

        calls[0] = MultiCall({
            target: _creditManager.universalAdapter(),
            callData: abi.encodeWithSelector(IUniversalAdapter.withdraw.selector, primaryToken, underlyingToPull)
        });

        uint256 returnedAmount = IERC20(primaryToken).balanceOf(address(this));
        IERC20(primaryToken).safeTransfer(to, returnedAmount);

        actualTokenAmounts = new uint256[](1);
        actualTokenAmounts[0] = returnedAmount;
    }

    function _verifyInstances(
        uint256 convexPoolId,
        address depositToken_,
        address primaryToken_
    ) internal {
        ICreditFacade creditFacade = _creditFacade;
        ICurveV1Adapter curveAdapter_ = ICurveV1Adapter(curveAdapter);
        IConvexV1BoosterAdapter convexAdapter_ = IConvexV1BoosterAdapter(convexAdapter);

        require(creditFacade.isTokenAllowed(primaryToken_), ExceptionsLibrary.INVALID_TOKEN);
        creditFacade.enableToken(depositToken_);

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
        IBooster.PoolInfo memory poolInfo = convexAdapter_.poolInfo(convexPoolId);
        convexOutputToken = poolInfo.token;
        require(lpToken == poolInfo.lptoken, ExceptionsLibrary.INVALID_TARGET);
    }

    function supportsInterface(bytes4 interfaceId) public view override(IERC165, IntegrationVault) returns (bool) {
        return IntegrationVault.supportsInterface(interfaceId) || interfaceId == type(IGearboxVault).interfaceId;
    }

    function updateTargetMarginalFactor(uint256 marginalFactorD_) external {
        require(_isApprovedOrOwner(msg.sender));

        (, , uint256 allAssetsValue) = _calculateDesiredTotalValue();
        marginalFactorD = marginalFactorD_;
        (, uint256 realValueWithMargin, ) = _calculateDesiredTotalValue();

        _adjustPosition(realValueWithMargin, allAssetsValue, 0);
    }

    function _isReclaimForbidden(address) internal pure override returns (bool) {
        return false;
    }

    function _adjustPosition(
        uint256 underlyingWant,
        uint256 underlyingCurrent,
        uint256 underlyingTokenToOutputObligation
    ) internal {
        ICreditFacade creditFacade = _creditFacade;

        uint256 currentAmount = IERC20(primaryToken).balanceOf(creditAccount);

        if (underlyingWant >= underlyingCurrent + underlyingTokenToOutputObligation) {
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
                    delta + currentAmount - underlyingTokenToOutputObligation,
                    primaryIndex,
                    0
                )
            });

            calls[2] = MultiCall({
                target: convexAdapter,
                callData: abi.encodeWithSelector(IBooster.depositAll.selector, poolId, false)
            });

            creditFacade.multicall(calls);
        } else {
            if (underlyingWant >= underlyingCurrent) {
                uint256 toMint = underlyingWant - underlyingCurrent;
                MultiCall[] memory calls = new MultiCall[](1);
                calls[0] = MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeWithSelector(ICreditFacade.increaseDebt.selector, toMint)
                });
                creditFacade.multicall(calls);
                underlyingCurrent = underlyingWant;
            }

            uint256 delta = underlyingCurrent - underlyingWant + underlyingTokenToOutputObligation;

            if (currentAmount >= delta) {
                MultiCall[] memory calls = new MultiCall[](1);
                calls[0] = MultiCall({
                    target: address(creditFacade),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });
                creditFacade.multicall(calls);
            } else {
                uint256 convexToOutput = _calcConvexTokensToOutput(delta - currentAmount);

                MultiCall[] memory calls = new MultiCall[](3);
                calls[0] = MultiCall({
                    target: convexAdapter,
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
            }
        }
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

    function _calcConvexTokensToOutput(uint256 underlyingAmount) internal view returns (uint256) {
        uint256 amount = IERC20(convexOutputToken).balanceOf(creditAccount);

        IPriceOracleV2 oracle = IPriceOracleV2(_creditManager.priceOracle());
        uint256 valueConvexToUsd = oracle.convertToUSD(amount, convexOutputToken);
        uint256 valueConvexToUnderlying = oracle.convertFromUSD(valueConvexToUsd, primaryToken);

        return FullMath.mulDiv(amount, underlyingAmount, valueConvexToUnderlying);
    }
}
