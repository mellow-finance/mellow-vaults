// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/OracleLibrary.sol";

contract UniV3Helper {
    function liquidityToTokenAmounts(
        uint128 liquidity,
        IUniswapV3Pool pool,
        uint256 uniV3Nft,
        INonfungiblePositionManager positionManager
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
        IUniswapV3Pool pool,
        uint256 uniV3Nft,
        INonfungiblePositionManager positionManager
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

    function _getFeeGrowthInside(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        (, , uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128, , , , ) = pool.ticks(tickLower);
        (, , uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128, , , , ) = pool.ticks(tickUpper);

        // calculate fee growth below
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (tickCurrent >= tickLower) {
            feeGrowthBelow0X128 = lowerFeeGrowthOutside0X128;
            feeGrowthBelow1X128 = lowerFeeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lowerFeeGrowthOutside0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lowerFeeGrowthOutside1X128;
        }

        // calculate fee growth above
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (tickCurrent < tickUpper) {
            feeGrowthAbove0X128 = upperFeeGrowthOutside0X128;
            feeGrowthAbove1X128 = upperFeeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upperFeeGrowthOutside0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upperFeeGrowthOutside1X128;
        }

        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }

    function calculatePositionInfo(
        INonfungiblePositionManager positionManager,
        IUniswapV3Pool pool,
        uint256 uniV3Nft
    )
        external
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        (
            ,
            ,
            ,
            ,
            ,
            tickLower,
            tickUpper,
            liquidity,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128,
            tokensOwed0,
            tokensOwed1
        ) = positionManager.positions(uniV3Nft);

        if (liquidity == 0) {
            return (tickLower, tickUpper, liquidity, tokensOwed0, tokensOwed1);
        }

        uint256 feeGrowthGlobal0X128 = pool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1X128 = pool.feeGrowthGlobal1X128();
        (, int24 tick, , , , , ) = pool.slot0();

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = _getFeeGrowthInside(
            pool,
            tickLower,
            tickUpper,
            tick,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128
        );

        tokensOwed0 += uint128(
            FullMath.mulDiv(feeGrowthInside0X128 - feeGrowthInside0LastX128, liquidity, CommonLibrary.Q128)
        );

        tokensOwed1 += uint128(
            FullMath.mulDiv(feeGrowthInside1X128 - feeGrowthInside1LastX128, liquidity, CommonLibrary.Q128)
        );
    }

    struct UniswapPositionParameters {
        uint256 nft;
        uint128 liquidity;
        int24 lowerTick;
        int24 upperTick;
        int24 averageTick;
        uint160 lowerPriceSqrtX96;
        uint160 upperPriceSqrtX96;
        uint160 averagePriceSqrtX96;
        uint256 averagePriceX96;
        uint160 spotPriceSqrtX96;
    }

    function getUniswapPositionParameters(
        int24 averageTick,
        uint160 sqrtSpotPriceX96,
        uint256 uniV3Nft,
        INonfungiblePositionManager positionManager
    ) external view returns (UniswapPositionParameters memory params) {
        params.averageTick = averageTick;
        params.averagePriceSqrtX96 = TickMath.getSqrtRatioAtTick(averageTick);
        params.averagePriceX96 = FullMath.mulDiv(
            params.averagePriceSqrtX96,
            params.averagePriceSqrtX96,
            CommonLibrary.Q96
        );
        params.spotPriceSqrtX96 = sqrtSpotPriceX96;
        if (uniV3Nft == 0) return params;
        params.nft = uniV3Nft;
        (, , , , , int24 lowerTick, int24 upperTick, uint128 liquidity, , , , ) = positionManager.positions(uniV3Nft);
        params.lowerTick = lowerTick;
        params.upperTick = upperTick;
        params.liquidity = liquidity;
        params.lowerPriceSqrtX96 = TickMath.getSqrtRatioAtTick(lowerTick);
        params.upperPriceSqrtX96 = TickMath.getSqrtRatioAtTick(upperTick);
    }

    function getAverageTickAndSqrtSpotPrice(IUniswapV3Pool pool_, uint32 oracleObservationDelta)
        external
        view
        returns (int24 averageTick, uint160 sqrtSpotPriceX96)
    {
        (, int24 tick, , , , , ) = pool_.slot0();
        sqrtSpotPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        bool withFail = false;
        (averageTick, , withFail) = OracleLibrary.consult(address(pool_), oracleObservationDelta);
        // Fails when we dont have observations, so return spot averageTick as this was the last trade price
        if (withFail) {
            averageTick = tick;
        }
    }
}
