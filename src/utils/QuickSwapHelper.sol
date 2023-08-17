// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PositionValue, LiquidityAmounts, TickMath, FullMath} from "../interfaces/external/quickswap/PositionValue.sol";
import "../interfaces/utils/IQuickSwapHelper.sol";
import "../interfaces/external/quickswap/IDragonLair.sol";

import "../libraries/external/DataStorageLibrary.sol";

contract QuickSwapHelper is IQuickSwapHelper {
    IAlgebraNonfungiblePositionManager public immutable positionManager;
    IAlgebraFactory public immutable factory;

    address public immutable quickToken;
    address public immutable dQuickToken;

    uint256 public constant Q128 = 2 ** 128;
    uint256 public constant Q96 = 2 ** 96;

    constructor(IAlgebraNonfungiblePositionManager positionManager_, address quickToken_, address dQuickToken_) {
        require(address(positionManager_) != address(0));
        positionManager = positionManager_;
        factory = IAlgebraFactory(positionManager.factory());
        quickToken = quickToken_;
        dQuickToken = dQuickToken_;
    }

    /// @inheritdoc IQuickSwapHelper
    function calculateTvl(
        uint256 nft,
        IQuickSwapVaultGovernance.StrategyParams memory strategyParams,
        IFarmingCenter farmingCenter,
        address token0
    ) public view returns (uint256[] memory tokenAmounts) {
        if (nft == 0) {
            return new uint256[](2);
        }
        IIncentiveKey.IncentiveKey memory key = strategyParams.key;
        (uint160 sqrtRatioX96, , , , , , ) = key.pool.globalState();
        tokenAmounts = new uint256[](2);
        (tokenAmounts[0], tokenAmounts[1]) = PositionValue.total(positionManager, nft, sqrtRatioX96);

        IAlgebraEternalFarming farming = farmingCenter.eternalFarming();

        (uint256 rewardAmount, uint256 bonusRewardAmount) = calculateCollectableRewards(farming, key, nft);
        rewardAmount += farming.rewards(address(this), key.rewardToken);
        bonusRewardAmount += farming.rewards(address(this), key.bonusRewardToken);

        rewardAmount = convertTokenToUnderlying(
            rewardAmount,
            address(key.rewardToken),
            strategyParams.rewardTokenToUnderlying,
            strategyParams.rewardPoolTimespan
        );
        bonusRewardAmount = convertTokenToUnderlying(
            bonusRewardAmount,
            address(key.bonusRewardToken),
            strategyParams.bonusTokenToUnderlying,
            strategyParams.rewardPoolTimespan
        );

        if (address(strategyParams.rewardTokenToUnderlying) == token0) {
            tokenAmounts[0] += rewardAmount;
        } else {
            tokenAmounts[1] += rewardAmount;
        }

        if (address(strategyParams.bonusTokenToUnderlying) == token0) {
            tokenAmounts[0] += bonusRewardAmount;
        } else {
            tokenAmounts[1] += bonusRewardAmount;
        }
    }

    /// @inheritdoc IQuickSwapHelper
    function liquidityToTokenAmounts(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint128 liquidity
    ) public view returns (uint256 amount0, uint256 amount1) {
        (, , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(nft);
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liquidity
        );
    }

    /// @inheritdoc IQuickSwapHelper
    function tokenAmountsToLiquidity(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint256[] memory amounts
    ) public view returns (uint128 liquidity) {
        (, , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(nft);
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            amounts[0],
            amounts[1]
        );
    }

    /// @inheritdoc IQuickSwapHelper
    function tokenAmountsToMaxLiquidity(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint256[] memory amounts
    ) public view returns (uint128 liquidity) {
        (, , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(nft);
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amounts[0]);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amounts[0]);
            uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amounts[1]);

            liquidity = liquidity0 > liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amounts[1]);
        }
    }

    /// @inheritdoc IQuickSwapHelper
    function calculateLiquidityToPull(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint256[] memory tokenAmounts
    ) public view returns (uint128 liquidity) {
        (, , , , , , uint128 positionLiquidity, , , , ) = positionManager.positions(nft);
        liquidity = tokenAmountsToMaxLiquidity(nft, sqrtRatioX96, tokenAmounts);
        liquidity = liquidity < positionLiquidity ? liquidity : positionLiquidity;
    }

    function increaseCumulative(
        uint32 currentTimestamp,
        IAlgebraEternalVirtualPool virtualPool
    ) public view returns (uint256 deltaTotalRewardGrowth0, uint256 deltaTotalRewardGrowth1) {
        unchecked {
            uint256 timeDelta = currentTimestamp - virtualPool.prevTimestamp(); // safe until timedelta > 136 years
            if (timeDelta == 0) return (0, 0);

            uint256 currentLiquidity = virtualPool.currentLiquidity(); // currentLiquidity is uint128

            if (currentLiquidity > 0) {
                uint256 rewardRate0 = virtualPool.rewardRate0();
                uint256 rewardRate1 = virtualPool.rewardRate1();
                uint256 rewardReserve0 = rewardRate0 > 0 ? virtualPool.rewardReserve0() : 0;
                uint256 rewardReserve1 = rewardRate1 > 0 ? virtualPool.rewardReserve1() : 0;

                if (rewardReserve0 > 0) {
                    uint256 reward0 = rewardRate0 * timeDelta;
                    if (reward0 > rewardReserve0) reward0 = rewardReserve0;
                    deltaTotalRewardGrowth0 = FullMath.mulDiv(reward0, Q128, currentLiquidity);
                }

                if (rewardReserve1 > 0) {
                    uint256 reward1 = rewardRate1 * timeDelta;
                    if (reward1 > rewardReserve1) reward1 = rewardReserve1;
                    deltaTotalRewardGrowth1 = FullMath.mulDiv(reward1, Q128, currentLiquidity);
                }
            }
        }
    }

    function calculateInnerFeesGrow(
        IAlgebraEternalVirtualPool virtualPool,
        int24 tickLower,
        int24 tickUpper
    ) public view returns (uint256 virtualPoolInnerRewardGrowth0, uint256 virtualPoolInnerRewardGrowth1) {
        (, , uint256 lowerOuterFeeGrowth0Token, uint256 lowerOuterFeeGrowth1Token, , , , ) = virtualPool.ticks(
            tickLower
        );

        (, , uint256 upperOuterFeeGrowth0Token, uint256 upperOuterFeeGrowth1Token, , , , ) = virtualPool.ticks(
            tickUpper
        );

        int24 currentTick = virtualPool.globalTick();

        uint256 totalFeeGrowth0Token = virtualPool.totalRewardGrowth0();
        uint256 totalFeeGrowth1Token = virtualPool.totalRewardGrowth1();
        (uint256 deltaTotalFeeGrowth0Token, uint256 deltaTotalFeeGrowth1Token) = increaseCumulative(
            uint32(block.timestamp),
            virtualPool
        );

        totalFeeGrowth0Token += deltaTotalFeeGrowth0Token;
        totalFeeGrowth1Token += deltaTotalFeeGrowth1Token;

        if (currentTick < tickUpper) {
            if (currentTick >= tickLower) {
                virtualPoolInnerRewardGrowth0 = totalFeeGrowth0Token - lowerOuterFeeGrowth0Token;
                virtualPoolInnerRewardGrowth1 = totalFeeGrowth1Token - lowerOuterFeeGrowth1Token;
            } else {
                virtualPoolInnerRewardGrowth0 = lowerOuterFeeGrowth0Token;
                virtualPoolInnerRewardGrowth1 = lowerOuterFeeGrowth1Token;
            }
            virtualPoolInnerRewardGrowth0 -= upperOuterFeeGrowth0Token;
            virtualPoolInnerRewardGrowth1 -= upperOuterFeeGrowth1Token;
        } else {
            virtualPoolInnerRewardGrowth0 = upperOuterFeeGrowth0Token - lowerOuterFeeGrowth0Token;
            virtualPoolInnerRewardGrowth1 = upperOuterFeeGrowth1Token - lowerOuterFeeGrowth1Token;
        }
    }

    /// @inheritdoc IQuickSwapHelper
    function calculateCollectableRewards(
        IAlgebraEternalFarming farming,
        IIncentiveKey.IncentiveKey memory key,
        uint256 nft
    ) public view returns (uint256 rewardAmount, uint256 bonusRewardAmount) {
        bytes32 incentiveId = keccak256(abi.encode(key));
        (uint256 totalReward, , address virtualPoolAddress, , , , ) = farming.incentives(incentiveId);
        if (totalReward == 0) {
            return (0, 0);
        }

        IAlgebraEternalVirtualPool virtualPool = IAlgebraEternalVirtualPool(virtualPoolAddress);
        (
            uint128 liquidity,
            int24 tickLower,
            int24 tickUpper,
            uint256 innerRewardGrowth0,
            uint256 innerRewardGrowth1
        ) = farming.farms(nft, incentiveId);
        if (liquidity == 0) {
            return (0, 0);
        }

        (uint256 virtualPoolInnerRewardGrowth0, uint256 virtualPoolInnerRewardGrowth1) = calculateInnerFeesGrow(
            virtualPool,
            tickLower,
            tickUpper
        );

        (rewardAmount, bonusRewardAmount) = (
            FullMath.mulDiv(virtualPoolInnerRewardGrowth0 - innerRewardGrowth0, liquidity, Q128),
            FullMath.mulDiv(virtualPoolInnerRewardGrowth1 - innerRewardGrowth1, liquidity, Q128)
        );
    }

    /// @inheritdoc IQuickSwapHelper
    function convertTokenToUnderlying(
        uint256 amount,
        address from,
        address to,
        uint32 timespan
    ) public view returns (uint256) {
        if (from == to || amount == 0) return amount;
        if (from == dQuickToken) {
            // unstake dQUICK to QUICK token
            amount = IDragonLair(dQuickToken).dQUICKForQUICK(amount);
            from = quickToken;
            if (from == to || amount == 0) return amount;
        }

        IAlgebraPool pool = IAlgebraPool(factory.poolByPair(from, to));
        (int24 averageTick, bool withFail) = DataStorageLibrary.consult(address(pool), timespan);
        require(!withFail, "Not enough observations in reward pool");

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (pool.token0() == to) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        }
        return FullMath.mulDiv(amount, priceX96, Q96);
    }
}
