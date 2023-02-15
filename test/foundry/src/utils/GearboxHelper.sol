// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/external/convex/ICvx.sol";
import "../interfaces/external/convex/Interfaces.sol";
import "../interfaces/external/gearbox/helpers/IPriceOracle.sol";
import "../libraries/external/FullMath.sol";
import "../interfaces/external/gearbox/ICreditFacade.sol";
import "../interfaces/external/gearbox/ICurveV1Adapter.sol";
import "../interfaces/external/gearbox/IConvexV1BaseRewardPoolAdapter.sol";
import "../interfaces/external/gearbox/IUniswapV3Adapter.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../interfaces/vaults/IGearboxVaultGovernance.sol";
import "../interfaces/external/gearbox/helpers/convex/IBooster.sol";
import "../interfaces/oracles/IOracle.sol";
import "forge-std/console2.sol";

contract GearboxHelper {
    using SafeERC20 for IERC20;

    uint256 public constant D9 = 10**9;
    uint256 public constant D27 = 10**27;
    uint256 public constant Q96 = 2**96;
    bytes4 public constant GET_REWARD_SELECTOR = 0x7050ccd9;

    ICreditFacade public creditFacade;
    ICreditManagerV2 public creditManager;

    address public curveAdapter;
    address public convexAdapter;
    address public primaryToken;
    address public depositToken;

    bool public is3crv;
    int128 public crv3Index;
    int128 public primaryIndex;
    address public convexOutputToken;
    address public crv3Pool;

    IGearboxVault public gearboxVault;
    IOracle public mellowOracle;
    IPriceOracleV2 public oracle;

    uint256 public vaultNft;

    constructor(address mellowOracle_) {
        mellowOracle = IOracle(mellowOracle_);
    }

    function setParameters(
        ICreditFacade creditFacade_,
        ICreditManagerV2 creditManager_,
        address primaryToken_,
        address depositToken_,
        uint256 nft_,
        address vaultGovernance
    ) external {
        require(address(gearboxVault) == address(0), ExceptionsLibrary.FORBIDDEN);
        creditFacade = creditFacade_;
        creditManager = creditManager_;
        primaryToken = primaryToken_;
        depositToken = depositToken_;
        vaultNft = nft_;

        gearboxVault = IGearboxVault(msg.sender);

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();
        crv3Pool = protocolParams.crv3Pool;

        oracle = IPriceOracleV2(creditManager.priceOracle());
    }

    function setAdapters(address curveAdapter_, address convexAdapter_) external {
        require(msg.sender == address(gearboxVault), ExceptionsLibrary.FORBIDDEN);
        curveAdapter = curveAdapter_;
        convexAdapter = convexAdapter_;
    }

    function calcWithdrawOneCoin(
        address adapter,
        uint256 amount,
        int128 index
    ) public view returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        return FullMath.mulDiv(ICurveV1Adapter(adapter).calc_withdraw_one_coin(10**16, index), amount, 10**16);
    }

    function calcTotalWithdraw(uint256 balance) public view returns (uint256) {
        if (!is3crv) {
            return calcWithdrawOneCoin(curveAdapter, balance, primaryIndex);
        } else {
            uint256 crv3LpBalance = calcWithdrawOneCoin(curveAdapter, balance, crv3Index);
            address crv3Adapter = creditManager.contractToAdapter(crv3Pool);
            return calcWithdrawOneCoin(crv3Adapter, crv3LpBalance, primaryIndex);
        }
    }

    function calcTotalValue(address creditAccount, address vaultGovernance)
        public
        view
        returns (uint256 currentAllAssetsValue)
    {
        (currentAllAssetsValue, ) = creditFacade.calcTotalValue(creditAccount);
        currentAllAssetsValue += calculateClaimableRewards(creditAccount, vaultGovernance);

        uint256 balance = IERC20(convexOutputToken).balanceOf(creditAccount);

        currentAllAssetsValue += calcTotalWithdraw(balance);
        currentAllAssetsValue -= oracle.convert(balance, convexOutputToken, primaryToken);
    }

    function calcTvl(address creditAccount, address vaultGovernance) external view returns (uint256) {
        address depositToken_ = depositToken;
        address primaryToken_ = primaryToken;
        ICreditManagerV2 creditManager_ = creditManager;

        uint256 primaryTokenAmount = 0;

        if (primaryToken_ != depositToken_) {
            primaryTokenAmount += IERC20(primaryToken_).balanceOf(address(gearboxVault));
        }

        if (creditAccount != address(0)) {
            uint256 currentAllAssetsValue = calcTotalValue(creditAccount, vaultGovernance);
            (, , uint256 borrowAmountWithInterestAndFees) = creditManager_.calcCreditAccountAccruedInterest(
                creditAccount
            );

            if (currentAllAssetsValue >= borrowAmountWithInterestAndFees) {
                primaryTokenAmount += currentAllAssetsValue - borrowAmountWithInterestAndFees;
            }
            console2.log("BORROW_INTEREST:", borrowAmountWithInterestAndFees);
        }

        if (primaryToken_ == depositToken_) {
            return primaryTokenAmount + IERC20(depositToken_).balanceOf(address(gearboxVault));
        } else {
            return
                oracle.convert(primaryTokenAmount, primaryToken_, depositToken_) +
                IERC20(depositToken_).balanceOf(address(gearboxVault));
        }
    }

    function verifyInstances() external returns (address, uint256) {
        require(msg.sender == address(gearboxVault), ExceptionsLibrary.FORBIDDEN);

        ICurveV1Adapter curveAdapter_ = ICurveV1Adapter(curveAdapter);
        IConvexV1BaseRewardPoolAdapter convexAdapter_ = IConvexV1BaseRewardPoolAdapter(convexAdapter);

        uint256 poolId = convexAdapter_.pid();
        address primaryToken_ = primaryToken;

        require(creditFacade.isTokenAllowed(primaryToken_), ExceptionsLibrary.INVALID_TOKEN);

        bool havePrimaryTokenInCurve = false;
        is3crv = false;

        for (uint256 i = 0; i < curveAdapter_.nCoins(); ++i) {
            address tokenI = curveAdapter_.coins(i);
            if (tokenI == primaryToken_) {
                primaryIndex = int128(int256(i));
                havePrimaryTokenInCurve = true;
            }
        }

        if (!havePrimaryTokenInCurve) {
            ICurveV1Adapter crv3Adapter = ICurveV1Adapter(creditManager.contractToAdapter(crv3Pool));
            address crv3Token = crv3Adapter.lp_token();

            for (uint256 i = 0; i < curveAdapter_.nCoins(); ++i) {
                address tokenI = curveAdapter_.coins(i);
                if (tokenI == crv3Token) {
                    crv3Index = int128(uint128(i));
                    is3crv = true;
                    for (uint256 j = 0; j < 3; ++j) {
                        address tokenJ = crv3Adapter.coins(j);
                        if (tokenJ == primaryToken_) {
                            primaryIndex = int128(int256(j));
                            havePrimaryTokenInCurve = true;
                        }
                    }
                }
            }
        }

        require(havePrimaryTokenInCurve, ExceptionsLibrary.INVALID_TOKEN);

        convexOutputToken = address(convexAdapter_.stakedPhantomToken());
        require(curveAdapter_.lp_token() == convexAdapter_.curveLPtoken(), ExceptionsLibrary.INVALID_TARGET);

        return (convexOutputToken, poolId);
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

    function calculateClaimableRewards(address creditAccount, address vaultGovernance)
        public
        view
        returns (uint256 totalValue)
    {
        uint256 earnedCrvAmount = IConvexV1BaseRewardPoolAdapter(convexAdapter).earned(creditAccount);

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();

        totalValue = oracle.convert(earnedCrvAmount, protocolParams.crv, primaryToken);
        console2.log("CRV:", oracle.convert(earnedCrvAmount, protocolParams.crv, primaryToken));
        totalValue += oracle.convert(
            calculateEarnedCvxAmountByEarnedCrvAmount(earnedCrvAmount, protocolParams.cvx),
            protocolParams.cvx,
            primaryToken
        );

        console2.log("CVX:", oracle.convert(
            calculateEarnedCvxAmountByEarnedCrvAmount(earnedCrvAmount, protocolParams.cvx),
            protocolParams.cvx,
            primaryToken
        ));

        IBaseRewardPool underlyingContract = IBaseRewardPool(creditManager.adapterToContract(convexAdapter));
        for (uint256 i = 0; i < underlyingContract.extraRewardsLength(); ++i) {
            IBaseRewardPool rewardsContract = IBaseRewardPool(underlyingContract.extraRewards(i));
            uint256 valueEarned = rewardsContract.earned(creditAccount);
            address tokenEarned = address(rewardsContract.rewardToken());
            (uint256[] memory pricesX96, ) = mellowOracle.priceX96(tokenEarned, primaryToken, 0x20);
            if (pricesX96.length != 0) {
                totalValue += FullMath.mulDiv(valueEarned, pricesX96[0], Q96);
            }
        }
    }

    function calculateDesiredTotalValue(
        address creditAccount,
        address vaultGovernance,
        uint256 marginalFactorD9
    ) external view returns (uint256 expectedAllAssetsValue, uint256 currentAllAssetsValue) {
        currentAllAssetsValue = calcTotalValue(creditAccount, vaultGovernance);

        (, , uint256 borrowAmountWithInterestAndFees) = creditManager.calcCreditAccountAccruedInterest(creditAccount);

        uint256 currentTvl = currentAllAssetsValue - borrowAmountWithInterestAndFees;
        expectedAllAssetsValue = FullMath.mulDiv(currentTvl, marginalFactorD9, D9);
    }

    function calcConvexTokensToWithdraw(uint256 desiredValueNominatedUnderlying, address creditAccount)
        public
        view
        returns (uint256)
    {
        uint256 currentConvexTokensAmount = IERC20(convexOutputToken).balanceOf(creditAccount);

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

    function calcRateRAY(address tokenFrom, address tokenTo) public view returns (uint256 rateRAY) {
        rateRAY = oracle.convert(D27, tokenFrom, tokenTo);
        if (rateRAY == 0) {
            (uint256[] memory pricesX96, ) = mellowOracle.priceX96(tokenFrom, tokenTo, 0x20);
            if (pricesX96.length != 0) {
                rateRAY = FullMath.mulDiv(pricesX96[0], D27, Q96);
            }
        }
    }

    function calculateAmountInMaximum(
        address fromToken,
        address toToken,
        uint256 amount,
        uint256 maxSlippageD9
    ) public view returns (uint256) {
        uint256 rateRAY = calcRateRAY(toToken, fromToken);
        uint256 amountInExpected = FullMath.mulDiv(amount, rateRAY, D27) + 1;
        return FullMath.mulDiv(amountInExpected, D9 + maxSlippageD9, D9) + 1;
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
            deadline: block.timestamp + 1,
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
        require(msg.sender == address(gearboxVault), ExceptionsLibrary.FORBIDDEN);

        address depositToken_ = depositToken;
        address primaryToken_ = primaryToken;

        if (depositToken_ == primaryToken_) {
            return;
        }

        uint256 currentDepositTokenAmount = IERC20(depositToken_).balanceOf(creditAccount);

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
            swapExactInput(depositToken_, primaryToken_, toSwap, vaultGovernance, creditAccount);
        }
    }

    function claimRewards(address vaultGovernance, address creditAccount) public {
        IGearboxVault gearboxVault_ = gearboxVault;
        address primaryToken_ = primaryToken;

        require(msg.sender == address(gearboxVault_), ExceptionsLibrary.FORBIDDEN);

        uint256 balance = IERC20(convexOutputToken).balanceOf(creditAccount);
        if (balance == 0) {
            return;
        }

        IBaseRewardPool underlyingContract = IBaseRewardPool(creditManager.adapterToContract(convexAdapter));

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();

        IGearboxVaultGovernance.StrategyParams memory strategyParams = IGearboxVaultGovernance(vaultGovernance)
            .strategyParams(vaultNft);

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory vaultParams = IGearboxVaultGovernance(
            vaultGovernance
        ).delayedProtocolPerVaultParams(vaultNft);

        address weth = creditManager.wethAddress();

        uint256 callsCount = 4;
        if (weth == primaryToken_ || weth == depositToken) {
            callsCount -= 1;
        }

        for (uint256 i = 0; i < underlyingContract.extraRewardsLength(); ++i) {
            address rewardToken = address(IBaseRewardPool(underlyingContract.extraRewards(i)).rewardToken());
            if (rewardToken != depositToken && rewardToken != primaryToken_ && rewardToken != weth) {
                callsCount += 1;
            }
        }

        MultiCall[] memory calls = new MultiCall[](callsCount);

        calls[0] = MultiCall({ // taking crv and cvx
            target: convexAdapter,
            callData: abi.encodeWithSelector(GET_REWARD_SELECTOR, creditAccount, true)
        });

        calls[1] = createUniswapMulticall(
            protocolParams.crv,
            weth,
            10000,
            vaultParams.univ3Adapter,
            protocolParams.maxSmallPoolsSlippageD9
        );

        calls[2] = createUniswapMulticall(
            protocolParams.cvx,
            weth,
            10000,
            vaultParams.univ3Adapter,
            protocolParams.maxSmallPoolsSlippageD9
        );

        uint256 pointer = 3;

        for (uint256 i = 2; i < 2 + underlyingContract.extraRewardsLength(); ++i) {
            address rewardToken = address(IBaseRewardPool(underlyingContract.extraRewards(i - 2)).rewardToken());
            if (rewardToken != depositToken && rewardToken != primaryToken_ && rewardToken != weth) {
                calls[pointer] = createUniswapMulticall(
                    rewardToken,
                    weth,
                    10000,
                    vaultParams.univ3Adapter,
                    protocolParams.maxSmallPoolsSlippageD9
                );
                pointer += 1;
            }
        }

        if (weth != primaryToken_ && weth != depositToken) {
            calls[callsCount - 1] = createUniswapMulticall(
                weth,
                primaryToken_,
                strategyParams.largePoolFeeUsed,
                vaultParams.univ3Adapter,
                protocolParams.maxSlippageD9
            );
        }

        gearboxVault_.multicall(calls);
    }

    function withdrawFromConvex(uint256 amount, address vaultGovernance) public {
        if (amount == 0) {
            return;
        }

        IGearboxVault gearboxVault_ = gearboxVault;

        require(msg.sender == address(gearboxVault_), ExceptionsLibrary.FORBIDDEN);

        address curveLpToken = ICurveV1Adapter(curveAdapter).lp_token();
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();

        if (!is3crv) {
            uint256 rateRAY = calcRateRAY(curveLpToken, primaryToken);

            MultiCall[] memory calls = new MultiCall[](2);

            calls[0] = MultiCall({
                target: convexAdapter,
                callData: abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector, amount, false)
            });

            calls[1] = MultiCall({
                target: curveAdapter,
                callData: abi.encodeWithSelector(
                    ICurveV1Adapter.remove_all_liquidity_one_coin.selector,
                    primaryIndex,
                    FullMath.mulDiv(rateRAY, D9 - protocolParams.maxCurveSlippageD9, D9)
                )
            });

            gearboxVault_.multicall(calls);
        } else {
            ICurveV1Adapter crv3Adapter = ICurveV1Adapter(creditManager.contractToAdapter(crv3Pool));
            address crv3Token = crv3Adapter.lp_token();

            uint256 rateRAY1 = calcRateRAY(curveLpToken, crv3Token);
            uint256 rateRAY2 = calcRateRAY(crv3Token, primaryToken);

            MultiCall[] memory calls = new MultiCall[](3);

            calls[0] = MultiCall({
                target: convexAdapter,
                callData: abi.encodeWithSelector(IBaseRewardPool.withdrawAndUnwrap.selector, amount, false)
            });

            calls[1] = MultiCall({
                target: curveAdapter,
                callData: abi.encodeWithSelector(
                    ICurveV1Adapter.remove_all_liquidity_one_coin.selector,
                    crv3Index,
                    FullMath.mulDiv(rateRAY1, D9 - protocolParams.maxCurveSlippageD9, D9)
                )
            });

            calls[2] = MultiCall({
                target: address(crv3Adapter),
                callData: abi.encodeWithSelector(
                    ICurveV1Adapter.remove_all_liquidity_one_coin.selector,
                    primaryIndex,
                    FullMath.mulDiv(rateRAY2, D9 - protocolParams.maxCurveSlippageD9, D9)
                )
            });

            gearboxVault_.multicall(calls);
        }
    }

    function depositToConvex(
        MultiCall memory debtManagementCall,
        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams,
        uint256 poolId
    ) public {
        IGearboxVault gearboxVault_ = gearboxVault;

        require(msg.sender == address(gearboxVault_), ExceptionsLibrary.FORBIDDEN);
        address curveLpToken = ICurveV1Adapter(curveAdapter).lp_token();

        if (!is3crv) {
            uint256 rateRAY = calcRateRAY(primaryToken, curveLpToken);

            MultiCall[] memory calls = new MultiCall[](3);

            calls[0] = debtManagementCall;

            calls[1] = MultiCall({
                target: curveAdapter,
                callData: abi.encodeWithSelector(
                    ICurveV1Adapter.add_all_liquidity_one_coin.selector,
                    primaryIndex,
                    FullMath.mulDiv(rateRAY, D9 - protocolParams.maxCurveSlippageD9, D9)
                )
            });

            calls[2] = MultiCall({
                target: creditManager.contractToAdapter(IConvexV1BaseRewardPoolAdapter(convexAdapter).operator()),
                callData: abi.encodeWithSelector(IBooster.depositAll.selector, poolId, true)
            });

            gearboxVault_.multicall(calls);
        } else {
            ICurveV1Adapter crv3Adapter = ICurveV1Adapter(creditManager.contractToAdapter(crv3Pool));
            address crv3Token = crv3Adapter.lp_token();

            uint256 rateRAY1 = calcRateRAY(primaryToken, crv3Token);
            uint256 rateRAY2 = calcRateRAY(crv3Token, curveLpToken);

            MultiCall[] memory calls = new MultiCall[](4);

            calls[0] = debtManagementCall;

            calls[1] = MultiCall({
                target: address(crv3Adapter),
                callData: abi.encodeWithSelector(
                    ICurveV1Adapter.add_all_liquidity_one_coin.selector,
                    primaryIndex,
                    FullMath.mulDiv(rateRAY1, D9 - protocolParams.maxCurveSlippageD9, D9)
                )
            });

            calls[2] = MultiCall({
                target: curveAdapter,
                callData: abi.encodeWithSelector(
                    ICurveV1Adapter.add_all_liquidity_one_coin.selector,
                    crv3Index,
                    FullMath.mulDiv(rateRAY2, D9 - protocolParams.maxCurveSlippageD9, D9)
                )
            });

            calls[3] = MultiCall({
                target: creditManager.contractToAdapter(IConvexV1BaseRewardPoolAdapter(convexAdapter).operator()),
                callData: abi.encodeWithSelector(IBooster.depositAll.selector, poolId, true)
            });

            gearboxVault_.multicall(calls);
        }
    }

    function adjustPosition(
        uint256 expectedAllAssetsValue,
        uint256 currentAllAssetsValue,
        address vaultGovernance,
        uint256 marginalFactorD9,
        uint256 poolId,
        address creditAccount_
    ) external {
        require(msg.sender == address(gearboxVault), ExceptionsLibrary.FORBIDDEN);

        claimRewards(vaultGovernance, creditAccount_);

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();
        ICreditFacade creditFacade_ = creditFacade;

        checkNecessaryDepositExchange(
            FullMath.mulDiv(expectedAllAssetsValue, D9, marginalFactorD9),
            vaultGovernance,
            creditAccount_
        );

        if (expectedAllAssetsValue >= currentAllAssetsValue) {
            uint256 delta = expectedAllAssetsValue - currentAllAssetsValue;

            MultiCall memory increaseDebtCall = MultiCall({
                target: address(creditFacade_),
                callData: abi.encodeWithSelector(ICreditFacade.increaseDebt.selector, delta)
            });

            depositToConvex(increaseDebtCall, protocolParams, poolId);
        } else {
            uint256 delta = currentAllAssetsValue - expectedAllAssetsValue;

            uint256 currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(creditAccount_);

            if (currentPrimaryTokenAmount >= delta) {
                MultiCall memory decreaseDebtCall = MultiCall({
                    target: address(creditFacade_),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });

                depositToConvex(decreaseDebtCall, protocolParams, poolId);
            } else {
                uint256 convexAmountToWithdraw = calcConvexTokensToWithdraw(
                    delta - currentPrimaryTokenAmount,
                    creditAccount_
                );
                withdrawFromConvex(convexAmountToWithdraw, vaultGovernance);

                currentPrimaryTokenAmount = IERC20(primaryToken).balanceOf(creditAccount_);
                if (currentPrimaryTokenAmount < delta) {
                    delta = currentPrimaryTokenAmount;
                }

                MultiCall[] memory decreaseCall = new MultiCall[](1);
                decreaseCall[0] = MultiCall({
                    target: address(creditFacade_),
                    callData: abi.encodeWithSelector(ICreditFacade.decreaseDebt.selector, delta)
                });

                gearboxVault.multicall(decreaseCall);
            }
        }

        emit PositionAdjusted(tx.origin, msg.sender, expectedAllAssetsValue);
    }

    function swapExactOutput(
        address fromToken,
        address toToken,
        uint256 amount,
        address vaultGovernance,
        address creditAccount
    ) external {
        require(msg.sender == address(gearboxVault), ExceptionsLibrary.FORBIDDEN);

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();

        IGearboxVaultGovernance.StrategyParams memory strategyParams = IGearboxVaultGovernance(vaultGovernance)
            .strategyParams(vaultNft);

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory vaultParams = IGearboxVaultGovernance(
            vaultGovernance
        ).delayedProtocolPerVaultParams(vaultNft);

        uint256 amountInMaximum = calculateAmountInMaximum(fromToken, toToken, amount, protocolParams.maxSlippageD9);

        ISwapRouter.ExactOutputParams memory uniParams = ISwapRouter.ExactOutputParams({
            path: abi.encodePacked(toToken, strategyParams.largePoolFeeUsed, fromToken), // exactOutput arguments are in reversed order
            recipient: creditAccount,
            deadline: block.timestamp + 1,
            amountOut: amount,
            amountInMaximum: amountInMaximum
        });

        MultiCall[] memory calls = new MultiCall[](1);

        calls[0] = MultiCall({
            target: vaultParams.univ3Adapter,
            callData: abi.encodeWithSelector(ISwapRouter.exactOutput.selector, uniParams)
        });

        gearboxVault.multicall(calls);
    }

    function swapExactInput(
        address fromToken,
        address toToken,
        uint256 amount,
        address vaultGovernance,
        address creditAccount
    ) public {
        require(msg.sender == address(gearboxVault), ExceptionsLibrary.FORBIDDEN);

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = IGearboxVaultGovernance(vaultGovernance)
            .delayedProtocolParams();

        IGearboxVaultGovernance.StrategyParams memory strategyParams = IGearboxVaultGovernance(vaultGovernance)
            .strategyParams(vaultNft);

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory vaultParams = IGearboxVaultGovernance(
            vaultGovernance
        ).delayedProtocolPerVaultParams(vaultNft);

        MultiCall[] memory calls = new MultiCall[](1);

        uint256 expectedOutput = oracle.convert(amount, fromToken, toToken);

        ISwapRouter.ExactInputParams memory inputParams = ISwapRouter.ExactInputParams({
            path: abi.encodePacked(fromToken, strategyParams.largePoolFeeUsed, toToken),
            recipient: creditAccount,
            deadline: block.timestamp + 1,
            amountIn: amount,
            amountOutMinimum: FullMath.mulDiv(expectedOutput, D9 - protocolParams.maxSlippageD9, D9)
        });

        calls[0] = MultiCall({ // swap deposit to primary token
            target: vaultParams.univ3Adapter,
            callData: abi.encodeWithSelector(ISwapRouter.exactInput.selector, inputParams)
        });

        gearboxVault.multicall(calls);
    }

    function openCreditAccount(address vaultGovernance, uint256 marginalFactorD9) external {
        IGearboxVault gearboxVault_ = gearboxVault;

        require(msg.sender == address(gearboxVault_), ExceptionsLibrary.FORBIDDEN);

        ICreditFacade creditFacade_ = creditFacade;
        address primaryToken_ = primaryToken;
        address depositToken_ = depositToken;

        uint256 minimalNecessaryAmount;

        {
            (uint256 minBorrowingLimit, ) = creditFacade_.limits();
            minimalNecessaryAmount = FullMath.mulDiv(minBorrowingLimit, D9, (marginalFactorD9 - D9)) + 1;
        }

        uint256 currentPrimaryTokenAmount = IERC20(primaryToken_).balanceOf(address(gearboxVault_));

        IGearboxVaultGovernance vaultGovernance_ = IGearboxVaultGovernance(vaultGovernance);
        uint256 vaultNft_ = vaultNft;

        IGearboxVaultGovernance.DelayedProtocolParams memory protocolParams = vaultGovernance_.delayedProtocolParams();
        IGearboxVaultGovernance.StrategyParams memory strategyParams = vaultGovernance_.strategyParams(vaultNft_);
        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory vaultParams = vaultGovernance_
            .delayedProtocolPerVaultParams(vaultNft_);

        if (depositToken_ != primaryToken_ && currentPrimaryTokenAmount < minimalNecessaryAmount) {
            ISwapRouter router = ISwapRouter(protocolParams.uniswapRouter);
            uint256 amountInMaximum = calculateAmountInMaximum(
                depositToken_,
                primaryToken_,
                minimalNecessaryAmount - currentPrimaryTokenAmount,
                protocolParams.maxSlippageD9
            );
            require(
                IERC20(depositToken_).balanceOf(address(gearboxVault_)) >= amountInMaximum,
                ExceptionsLibrary.INVARIANT
            );

            ISwapRouter.ExactOutputParams memory uniParams = ISwapRouter.ExactOutputParams({
                path: abi.encodePacked(primaryToken_, strategyParams.largePoolFeeUsed, depositToken_), // exactOutput arguments are in reversed order
                recipient: address(gearboxVault_),
                deadline: block.timestamp + 1,
                amountOut: minimalNecessaryAmount - currentPrimaryTokenAmount,
                amountInMaximum: amountInMaximum
            });

            gearboxVault_.swapExactOutput(router, uniParams, depositToken_, amountInMaximum);

            currentPrimaryTokenAmount = IERC20(primaryToken_).balanceOf(address(gearboxVault_));
        }

        require(currentPrimaryTokenAmount >= minimalNecessaryAmount, ExceptionsLibrary.LIMIT_UNDERFLOW);
        gearboxVault_.openCreditAccountInManager(currentPrimaryTokenAmount, vaultParams.referralCode);
        emit CreditAccountOpened(tx.origin, msg.sender, creditManager.creditAccounts(address(gearboxVault_)));
    }

    /// @notice Emitted when a credit account linked to this vault is opened in Gearbox
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param creditAccount Address of the opened credit account
    event CreditAccountOpened(address indexed origin, address indexed sender, address creditAccount);

    /// @notice Emitted when an adjusment of the position made in Gearbox
    /// @param origin Origin of the transaction (tx.origin)
    /// @param sender Sender of the call (msg.sender)
    /// @param newTotalAssetsValue New value of all assets (debt + real assets) of the vault
    event PositionAdjusted(address indexed origin, address indexed sender, uint256 newTotalAssetsValue);
}
