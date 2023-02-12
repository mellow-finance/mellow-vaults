// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/kyber/IPool.sol";
import "../interfaces/external/kyber/IFactory.sol";
import "../interfaces/external/kyber/periphery/IBasePositionManager.sol";

import "../libraries/CommonLibrary.sol";
import "../libraries/external/LiquidityMath.sol";
import "../libraries/external/QtyDeltaMath.sol";
import "../libraries/external/TickMath.sol";

contract KyberHelper {
    
    IBasePositionManager public immutable positionManager;

    constructor(IBasePositionManager positionManager_) {
        require(address(positionManager_) != address(0));
        positionManager = positionManager_;
    }

    function liquidityToTokenAmounts(
        uint128 liquidity,
        IPool pool,
        uint256 kyberNft
    ) external view returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](2);

        (IBasePositionManager.Position memory position, ) = positionManager.positions(kyberNft);

        (uint160 sqrtPriceX96, , ,) = pool.getPoolState();
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        (tokenAmounts[0], tokenAmounts[1]) = QtyDeltaMath.calcRequiredQtys(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            liquidity,
            false
        );
    }

    function tokenAmountsToLiquidity(
        uint256[] memory tokenAmounts,
        IPool pool,
        uint256 kyberNft
    ) external view returns (uint128 liquidity) {

        (IBasePositionManager.Position memory position, ) = positionManager.positions(kyberNft);

        (uint160 sqrtPriceX96, , ,) = pool.getPoolState();
        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        liquidity = LiquidityMath.getLiquidityFromQties(
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
            LiquidityMath.getLiquidityFromQty0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = LiquidityMath.getLiquidityFromQty0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = LiquidityMath.getLiquidityFromQty1(sqrtRatioAX96, sqrtRatioX96, amount1);

            liquidity = liquidity0 > liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = LiquidityMath.getLiquidityFromQty1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }

    /// @dev returns with "Invalid Token ID" for non-existent nfts
    function calculateTvlBySqrtPriceX96(uint256 kyberNft, uint160 sqrtPriceX96)
        public
        view
        returns (uint256[] memory tokenAmounts)
    {
        tokenAmounts = new uint256[](2);

        (IBasePositionManager.Position memory position, ) = positionManager.positions(kyberNft);

        uint160 sqrtPriceAX96 = TickMath.getSqrtRatioAtTick(position.tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtRatioAtTick(position.tickUpper);

        (tokenAmounts[0], tokenAmounts[1]) = QtyDeltaMath.calcRequiredQtys(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            position.liquidity,
            false
        );

        (uint256 feeAmount0, uint256 feeAmount1) = QtyDeltaMath.getQtysFromBurnRTokens(sqrtPriceX96, position.liquidity);
        tokenAmounts[0] += feeAmount0;
        tokenAmounts[1] += feeAmount1;
    }
    
}
