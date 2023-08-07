// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/external/pancakeswap/IPancakeV3Factory.sol";
import "../interfaces/external/pancakeswap/IMasterChef.sol";
import "../interfaces/vaults/IPancakeSwapVaultGovernance.sol";

import "../libraries/CommonLibrary.sol";
import "../interfaces/external/pancakeswap/libraries/OracleLibrary.sol";
import "../interfaces/external/pancakeswap/libraries/PositionValue.sol";
import "../interfaces/external/pancakeswap/ILMPool.sol";
import "../interfaces/external/pancakeswap/IPancakeV3LMPool.sol";

contract PancakeSwapHelper {
    IPancakeNonfungiblePositionManager public immutable positionManager;

    constructor(IPancakeNonfungiblePositionManager positionManager_) {
        require(address(positionManager_) != address(0));
        positionManager = positionManager_;
    }

    function liquidityToTokenAmounts(
        uint128 liquidity,
        IPancakeV3Pool pool,
        uint256 uniV3Nft
    ) external view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](2);
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(uniV3Nft);

        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (tokenAmounts[0], tokenAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liquidity
        );
    }

    function tokenAmountsToLiquidity(
        uint256[] memory tokenAmounts,
        IPancakeV3Pool pool,
        uint256 uniV3Nft
    ) external view returns (uint128 liquidity) {
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(uniV3Nft);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            tokenAmounts[0],
            tokenAmounts[1]
        );
    }

    function tokenAmountsToMaximalLiquidity(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) external pure returns (uint128 liquidity) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);

            liquidity = liquidity0 > liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }

    /// @dev returns with "Invalid Token ID" for non-existent nfts
    function getPoolByNft(uint256 uniV3Nft) public view returns (IPancakeV3Pool pool) {
        (, , address token0, address token1, uint24 fee, , , , , , , ) = positionManager.positions(uniV3Nft);
        pool = IPancakeV3Pool(IPancakeV3Factory(positionManager.factory()).getPool(token0, token1, fee));
    }

    /// @dev returns with "Invalid Token ID" for non-existent nfts
    function getFeesByNft(uint256 uniV3Nft) external view returns (uint256 fees0, uint256 fees1) {
        (fees0, fees1) = PositionValue.fees(positionManager, uniV3Nft);
    }

    /// @dev returns with "Invalid Token ID" for non-existent nfts
    function calculateTvlBySqrtPriceX96(
        uint256 uniV3Nft,
        uint160 sqrtPriceX96
    ) public view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](2);
        (tokenAmounts[0], tokenAmounts[1]) = PositionValue.total(positionManager, uniV3Nft, sqrtPriceX96);
    }

    /// @dev returns with "Invalid Token ID" for non-existent nfts
    function calculateTvlByMinMaxPrices(
        uint256 uniV3Nft,
        uint256 minPriceX96,
        uint256 maxPriceX96
    ) public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        minTokenAmounts = new uint256[](2);
        maxTokenAmounts = new uint256[](2);
        (uint256 fees0, uint256 fees1) = PositionValue.fees(positionManager, uniV3Nft);

        uint160 minSqrtPriceX96 = uint160(CommonLibrary.sqrtX96(minPriceX96));
        uint160 maxSqrtPriceX96 = uint160(CommonLibrary.sqrtX96(maxPriceX96));
        (uint256 amountMin0, uint256 amountMin1) = PositionValue.principal(positionManager, uniV3Nft, minSqrtPriceX96);
        (uint256 amountMax0, uint256 amountMax1) = PositionValue.principal(positionManager, uniV3Nft, maxSqrtPriceX96);

        if (amountMin0 > amountMax0) (amountMin0, amountMax0) = (amountMax0, amountMin0);
        if (amountMin1 > amountMax1) (amountMin1, amountMax1) = (amountMax1, amountMin1);

        minTokenAmounts[0] = amountMin0 + fees0;
        maxTokenAmounts[0] = amountMax0 + fees0;
        minTokenAmounts[1] = amountMin1 + fees1;
        maxTokenAmounts[1] = amountMax1 + fees1;
    }

    function getTickDeviationForTimeSpan(
        int24 tick,
        address pool_,
        uint32 secondsAgo
    ) external view returns (bool withFail, int24 deviation) {
        int24 averageTick;
        (averageTick, , withFail) = OracleLibrary.consult(pool_, secondsAgo);
        deviation = tick - averageTick;
    }

    /// @dev calculates the distribution of tokens that can be added to the position after swap for given capital in token 0
    function getPositionTokenAmountsByCapitalOfToken0(
        uint256 lowerPriceSqrtX96,
        uint256 upperPriceSqrtX96,
        uint256 spotPriceForSqrtFormulasX96,
        uint256 spotPriceX96,
        uint256 capital
    ) external pure returns (uint256 token0Amount, uint256 token1Amount) {
        // sqrt(upperPrice) * (sqrt(price) - sqrt(lowerPrice))
        uint256 lowerPriceTermX96 = FullMath.mulDiv(
            upperPriceSqrtX96,
            spotPriceForSqrtFormulasX96 - lowerPriceSqrtX96,
            CommonLibrary.Q96
        );
        // sqrt(price) * (sqrt(upperPrice) - sqrt(price))
        uint256 upperPriceTermX96 = FullMath.mulDiv(
            spotPriceForSqrtFormulasX96,
            upperPriceSqrtX96 - spotPriceForSqrtFormulasX96,
            CommonLibrary.Q96
        );

        token1Amount = FullMath.mulDiv(
            FullMath.mulDiv(capital, spotPriceX96, CommonLibrary.Q96),
            lowerPriceTermX96,
            lowerPriceTermX96 + upperPriceTermX96
        );

        token0Amount = capital - FullMath.mulDiv(token1Amount, CommonLibrary.Q96, spotPriceX96);
    }

    function calculateCakePriceX96InUnderlying(
        IPancakeSwapVaultGovernance.StrategyParams memory params
    ) public view returns (uint256 priceX96) {
        IPancakeV3Pool poolForSwap = IPancakeV3Pool(params.poolForSwap);
        (int24 averageTick, , bool withFail) = OracleLibrary.consult(params.poolForSwap, params.averageTickTimespan);
        require(!withFail, ExceptionsLibrary.INVALID_STATE);
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);
        priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, CommonLibrary.Q96);
        if (poolForSwap.token0() == params.underlyingToken) {
            priceX96 = FullMath.mulDiv(CommonLibrary.Q96, CommonLibrary.Q96, priceX96);
        }
    }

    function _accumulateReward(
        uint32 currTimestamp,
        IPancakeV3LMPool lmPool
    ) private view returns (uint256 rewardGrowthGlobalX128) {
        unchecked {
            uint32 lastRewardTimestamp = lmPool.lastRewardTimestamp();
            rewardGrowthGlobalX128 = lmPool.rewardGrowthGlobalX128();
            if (currTimestamp <= lastRewardTimestamp) {
                return rewardGrowthGlobalX128;
            }

            if (lmPool.lmLiquidity() != 0) {
                (uint256 rewardPerSecond, uint256 endTime) = lmPool.masterChef().getLatestPeriodInfo(
                    address(lmPool.pool())
                );

                uint32 endTimestamp = uint32(endTime);
                uint32 duration;
                if (endTimestamp > currTimestamp) {
                    duration = currTimestamp - lastRewardTimestamp;
                } else if (endTimestamp > lastRewardTimestamp) {
                    duration = endTimestamp - lastRewardTimestamp;
                }

                if (duration != 0) {
                    rewardGrowthGlobalX128 += FullMath.mulDiv(
                        duration,
                        FullMath.mulDiv(rewardPerSecond, FixedPoint128.Q128, lmPool.REWARD_PRECISION()),
                        lmPool.lmLiquidity()
                    );
                }
            }
        }
    }

    function _getLMTicks(int24 tick, IPancakeV3LMPool lmPool) internal view returns (ILMPool.Info memory info) {
        unchecked {
            try lmPool.oldLMPool().lmTicks(tick) returns (ILMPool.Info memory info_) {
                info = info_;
            } catch {
                // When tick had updated in thirdLMPool , read tick info from third LMPool, or read from second LMPool , if not , read from firstLMPool.
                if (lmPool.thirdLMPool().lmTicksFlag(tick)) {
                    (info.liquidityGross, info.liquidityNet, info.rewardGrowthOutsideX128) = lmPool
                        .thirdLMPool()
                        .lmTicks(tick);
                } else if (lmPool.secondLMPool().lmTicksFlag(tick)) {
                    (info.liquidityGross, info.liquidityNet, info.rewardGrowthOutsideX128) = lmPool
                        .secondLMPool()
                        .lmTicks(tick);
                } else {
                    (info.liquidityGross, info.liquidityNet, info.rewardGrowthOutsideX128) = lmPool
                        .firstLMPool()
                        .lmTicks(tick);
                }
            }
        }
    }

    function _getRewardGrowthInsideInternal(
        int24 tickLower,
        int24 tickUpper,
        IPancakeV3LMPool lmPool,
        uint256 rewardGrowthGlobalX128
    ) internal view returns (uint256 rewardGrowthInsideX128, bool isNegative) {
        unchecked {
            (, int24 tick, , , , , ) = lmPool.pool().slot0();
            ILMPool.Info memory lower;
            if (lmPool.lmTicksFlag(tickLower)) {
                lower = lmPool.lmTicks(tickLower);
            } else {
                lower = _getLMTicks(tickLower, lmPool);
            }
            ILMPool.Info memory upper;
            if (lmPool.lmTicksFlag(tickUpper)) {
                upper = lmPool.lmTicks(tickUpper);
            } else {
                upper = _getLMTicks(tickUpper, lmPool);
            }

            // calculate reward growth below
            uint256 rewardGrowthBelowX128;
            if (tick >= tickLower) {
                rewardGrowthBelowX128 = lower.rewardGrowthOutsideX128;
            } else {
                rewardGrowthBelowX128 = rewardGrowthGlobalX128 - lower.rewardGrowthOutsideX128;
            }

            // calculate reward growth above
            uint256 rewardGrowthAboveX128;
            if (tick < tickUpper) {
                rewardGrowthAboveX128 = upper.rewardGrowthOutsideX128;
            } else {
                rewardGrowthAboveX128 = rewardGrowthGlobalX128 - upper.rewardGrowthOutsideX128;
            }

            rewardGrowthInsideX128 = rewardGrowthGlobalX128 - rewardGrowthBelowX128 - rewardGrowthAboveX128;
            isNegative = (rewardGrowthBelowX128 + rewardGrowthAboveX128) > rewardGrowthGlobalX128;
        }
    }

    function _getNegativeRewardGrowthInsideInitValue(
        int24 tickLower,
        int24 tickUpper,
        IPancakeV3LMPool lmPool
    ) internal view returns (uint256 initValue) {
        unchecked {
            try lmPool.checkOldLMPool(tickLower, tickUpper) returns (bool flag) {
                if (flag) {
                    initValue = lmPool.negativeRewardGrowthInsideInitValue(tickLower, tickUpper);
                } else {
                    initValue = lmPool.oldLMPool().negativeRewardGrowthInsideInitValue(tickLower, tickUpper);
                }
            } catch {
                // If already chekced third LMPool , use current negativeRewardGrowthInsideInitValue.
                if (lmPool.checkThirdLMPool(tickLower, tickUpper)) {
                    initValue = lmPool.negativeRewardGrowthInsideInitValue(tickLower, tickUpper);
                } else {
                    bool checkSecondLMPoolFlagInThirdLMPool = lmPool.thirdLMPool().checkSecondLMPool(
                        tickLower,
                        tickUpper
                    );
                    // If already checked second LMPool , use third LMPool negativeRewardGrowthInsideInitValue.
                    if (checkSecondLMPoolFlagInThirdLMPool) {
                        initValue = lmPool.thirdLMPool().negativeRewardGrowthInsideInitValue(tickLower, tickUpper);
                    } else {
                        // If not checked second LMPool , use second LMPool negativeRewardGrowthInsideInitValue.
                        initValue = lmPool.secondLMPool().negativeRewardGrowthInsideInitValue(tickLower, tickUpper);
                    }
                }
            }
        }
    }

    function _getRewardGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        IPancakeV3LMPool lmPool,
        uint256 rewardGrowthGlobalX128
    ) private view returns (uint256 rewardGrowthInsideX128) {
        unchecked {
            (rewardGrowthInsideX128, ) = _getRewardGrowthInsideInternal(
                tickLower,
                tickUpper,
                lmPool,
                rewardGrowthGlobalX128
            );
            uint256 initValue = _getNegativeRewardGrowthInsideInitValue(tickLower, tickUpper, lmPool);
            rewardGrowthInsideX128 = rewardGrowthInsideX128 - initValue;
        }
    }

    function calculateActualPendingCake(address masterChef, uint256 nft) public view returns (uint256 reward) {
        unchecked {
            IMasterChef.UserPositionInfo memory positionInfo = IMasterChef(masterChef).userPositionInfos(nft);
            if (positionInfo.liquidity == 0 && positionInfo.reward == 0) return 0;

            IMasterChef.PoolInfo memory pool = IMasterChef(masterChef).poolInfo(positionInfo.pid);
            ILMPool LMPool = ILMPool(pool.v3Pool.lmPool());
            if (address(LMPool) != address(0)) {
                // Update rewardGrowthInside
                uint256 rewardGrowthGlobalX128 = _accumulateReward(
                    uint32(block.timestamp),
                    IPancakeV3LMPool(address(LMPool))
                );

                uint256 rewardGrowthInside = _getRewardGrowthInside(
                    positionInfo.tickLower,
                    positionInfo.tickUpper,
                    IPancakeV3LMPool(address(LMPool)),
                    rewardGrowthGlobalX128
                );

                // Check overflow
                if (
                    rewardGrowthInside > positionInfo.rewardGrowthInside &&
                    type(uint256).max / (rewardGrowthInside - positionInfo.rewardGrowthInside) >
                    positionInfo.boostLiquidity
                )
                    reward =
                        ((rewardGrowthInside - positionInfo.rewardGrowthInside) * positionInfo.boostLiquidity) /
                        CommonLibrary.Q128;
                positionInfo.rewardGrowthInside = rewardGrowthInside;
            }

            reward += positionInfo.reward;
        }
    }

    function calculateAmountOfCakeInUnderlying(
        IPancakeSwapVaultGovernance.StrategyParams memory params,
        address masterChef,
        uint256 uniV3Nft
    ) public view returns (uint256) {
        uint256 cakeAmount = calculateActualPendingCake(masterChef, uniV3Nft);
        if (cakeAmount == 0) return 0;
        return FullMath.mulDiv(cakeAmount, calculateCakePriceX96InUnderlying(params), CommonLibrary.Q96);
    }

    function getMinMaxPrice(
        address[] memory vaultTokens,
        IOracle oracle,
        uint32 safetyIndicesSet
    ) public view returns (uint256 minPriceX96, uint256 maxPriceX96) {
        (uint256[] memory prices, ) = oracle.priceX96(vaultTokens[0], vaultTokens[1], safetyIndicesSet);
        require(prices.length >= 1, ExceptionsLibrary.INVARIANT);
        minPriceX96 = prices[0];
        maxPriceX96 = prices[0];
        for (uint32 i = 1; i < prices.length; ++i) {
            if (prices[i] < minPriceX96) {
                minPriceX96 = prices[i];
            } else if (prices[i] > maxPriceX96) {
                maxPriceX96 = prices[i];
            }
        }
    }

    function tvl(
        uint256 uniV3Nft_,
        address vaultGovernance_,
        uint256 vaultNft,
        IPancakeV3Pool pool,
        address[] memory vaultTokens,
        address masterChef
    ) public view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts) {
        if (uniV3Nft_ == 0) {
            return (new uint256[](2), new uint256[](2));
        }

        IPancakeSwapVaultGovernance.DelayedProtocolParams memory params = IPancakeSwapVaultGovernance(vaultGovernance_)
            .delayedProtocolParams();
        IPancakeSwapVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IPancakeSwapVaultGovernance(
            vaultGovernance_
        ).delayedStrategyParams(vaultNft);
        // cheaper way to calculate tvl by spot price
        if (delayedStrategyParams.safetyIndicesSet == 2) {
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            minTokenAmounts = calculateTvlBySqrtPriceX96(uniV3Nft_, sqrtPriceX96);
            maxTokenAmounts = new uint256[](2);
            maxTokenAmounts[0] = minTokenAmounts[0];
            maxTokenAmounts[1] = minTokenAmounts[1];
        } else {
            (uint256 minPriceX96, uint256 maxPriceX96) = getMinMaxPrice(
                vaultTokens,
                params.oracle,
                delayedStrategyParams.safetyIndicesSet
            );
            (minTokenAmounts, maxTokenAmounts) = calculateTvlByMinMaxPrices(uniV3Nft_, minPriceX96, maxPriceX96);
        }

        // adding rewards
        {
            IPancakeSwapVaultGovernance.StrategyParams memory strategyParams = IPancakeSwapVaultGovernance(
                address(vaultGovernance_)
            ).strategyParams(vaultNft);
            uint256 amountOfCakeInUnderlying = calculateAmountOfCakeInUnderlying(strategyParams, masterChef, uniV3Nft_);

            if (amountOfCakeInUnderlying > 0) {
                if (vaultTokens[0] == strategyParams.underlyingToken) {
                    minTokenAmounts[0] += amountOfCakeInUnderlying;
                    maxTokenAmounts[0] += amountOfCakeInUnderlying;
                } else if (vaultTokens[1] == strategyParams.underlyingToken) {
                    minTokenAmounts[1] += amountOfCakeInUnderlying;
                    maxTokenAmounts[1] += amountOfCakeInUnderlying;
                } else {
                    revert(ExceptionsLibrary.INVALID_STATE);
                }
            }
        }
    }
}
