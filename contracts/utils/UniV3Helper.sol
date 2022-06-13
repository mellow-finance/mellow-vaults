// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/LiquidityAmounts.sol";

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
        uint128 prevTokensOwed0;
        uint128 prevTokensOwed1;
        uint256 prevFeeGrowthInside0LastX128;
        uint256 prevFeeGrowthInside1LastX128;

        (
            ,
            ,
            ,
            ,
            ,
            tickLower,
            tickUpper,
            liquidity,
            prevFeeGrowthInside0LastX128,
            prevFeeGrowthInside1LastX128,
            prevTokensOwed0,
            prevTokensOwed1
        ) = positionManager.positions(uniV3Nft);

        uint256 curFeeGrowthInside0LastX128 = pool.feeGrowthGlobal0X128();
        uint256 curFeeGrowthInside1LastX128 = pool.feeGrowthGlobal1X128();

        tokensOwed0 =
            prevTokensOwed0 +
            uint128(
                FullMath.mulDiv(
                    curFeeGrowthInside0LastX128 - prevFeeGrowthInside0LastX128,
                    liquidity,
                    CommonLibrary.Q128
                )
            );

        tokensOwed1 =
            prevTokensOwed1 +
            uint128(
                FullMath.mulDiv(
                    curFeeGrowthInside1LastX128 - prevFeeGrowthInside1LastX128,
                    liquidity,
                    CommonLibrary.Q128
                )
            );
    }
}
