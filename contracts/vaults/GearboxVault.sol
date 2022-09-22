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
import "../interfaces/external/gearbox/IConvexV1BoosterAdapter.sol";
import "../interfaces/external/gearbox/IConvexV1BaseRewardPoolAdapter.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IGearboxVault.sol";
import "../interfaces/vaults/IGearboxVaultGovernance.sol";

contract GearboxVault is IGearboxVault, IntegrationVault {
    using SafeERC20 for IERC20;

    uint256 public constant DENOMINATOR = 10**9;
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
        poolId = params.convexPoolId;
        marginalFactorD = params.initialMarginalValue;

        ICreditFacade creditFacade = ICreditFacade(params.facade);
        ICreditManagerV2 creditManager = ICreditManagerV2(creditFacade.creditManager());

        _creditFacade = creditFacade;
        _creditManager = creditManager;

        _verifyInstances(poolId, depositToken, primaryToken);
        uint256 amount = _pullExistentials[0];

        creditFacade.openCreditAccount(amount, address(this), 0, protocolParams.referralCode);
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
        _adjustPosition(total, previousTotal, false);
    }

    function _pull(
        address to,
        uint256[] memory tokenAmounts,
        bytes memory
    ) internal override returns (uint256[] memory actualTokenAmounts) {
        require(tokenAmounts.length == 1, ExceptionsLibrary.INVALID_LENGTH);
        uint256 amount = tokenAmounts[0];

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory params = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolPerVaultParams(_nft);

        (uint256 realValue, , uint256 previousTotal) = _calculateDesiredTotalValue();

        _adjustPosition(realValue, previousTotal, true);
        if (primaryToken != depositToken) {
            MultiCall[] memory calls = new MultiCall[](1);

            calls[0] = MultiCall({ // swap deposit to primary token
                target: params.depositToPrimaryTokenPool,
                callData: abi.encodeWithSelector(
                    IUniswapV3Adapter.exactAllInputSingle.selector,
                    abi.encode(primaryToken, 500, depositToken),
                    block.timestamp + 900,
                    0
                )
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

        if (underlyingWant >= underlyingCurrent && !forceToClose) {
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
                target: convexAdapter,
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

                creditFacade.multicall(calls);
            }
        }
    }

    function _checkDepositExchange(uint256 underlyingWant) internal {
        if (depositToken == primaryToken) {
            return;
        }

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory params = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolPerVaultParams(_nft);

        uint256 amount = IERC20(depositToken).balanceOf(creditAccount);
        IPriceOracleV2 oracle = IPriceOracleV2(_creditManager.priceOracle());
        uint256 valueConvexToUsd = oracle.convertToUSD(amount, convexOutputToken);
        uint256 valueConvexToUnderlying = oracle.convertFromUSD(valueConvexToUsd, primaryToken);

        if (valueConvexToUnderlying > underlyingWant) {
            uint256 toSwap = FullMath.mulDiv(amount, valueConvexToUnderlying - underlyingWant, valueConvexToUnderlying);
            MultiCall[] memory calls = new MultiCall[](0);

            calls[0] = MultiCall({ // swap deposit to primary token
                target: params.depositToPrimaryTokenPool,
                callData: abi.encodeWithSelector(
                    ISwapRouter.exactInputSingle.selector,
                    _creditManager.getCreditAccountOrRevert(address(this)),
                    abi.encode(depositToken, 500, primaryToken),
                    block.timestamp + 900,
                    toSwap,
                    0
                )
            });

            _creditFacade.multicall(calls);
        }
    }

    function _claimRewards() internal {
        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory params = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolPerVaultParams(_nft);
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(
            address(_vaultGovernance)
        ).delayedProtocolParams();

        MultiCall[] memory calls = new MultiCall[](4);

        calls[0] = MultiCall({ // taking crv and cvx
            target: IConvexV1BoosterAdapter(convexAdapter).stakerRewards(),
            callData: abi.encodeWithSelector(GET_REWARD_SELECTOR, address(this), false)
        });

        calls[1] = MultiCall({ // swap crv to weth
            target: protocolParams.crvEthPool,
            callData: abi.encodeWithSelector(ICurvePool.exchange.selector, 0, 1, 0)
        });

        calls[2] = MultiCall({ // swap cvx to weth
            target: protocolParams.cvxEthPool,
            callData: abi.encodeWithSelector(ICurvePool.exchange.selector, 0, 1, 0)
        });

        calls[3] = MultiCall({ // swap weth to primary token
            target: params.ethToPrimaryTokenPool,
            callData: abi.encodeWithSelector(
                IUniswapV3Adapter.exactAllInputSingle.selector,
                abi.encode(protocolParams.wethAddress, 500, params.primaryToken),
                block.timestamp + 900,
                0
            )
        });

        _creditFacade.multicall(calls);
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
