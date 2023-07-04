// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PositionValue, LiquidityAmounts, TickMath} from "../interfaces/external/algebrav2/PositionValue.sol";

import "../interfaces/utils/ICamelotHelper.sol";

contract CamelotHelper is ICamelotHelper {
    IAlgebraNonfungiblePositionManager public immutable positionManager;
    IAlgebraFactory public immutable factory;

    address public immutable token0;
    address public immutable token1;

    IAlgebraPool public immutable pool;

    uint256 public constant Q128 = 2 ** 128;
    uint256 public constant Q96 = 2 ** 96;

    constructor(IAlgebraNonfungiblePositionManager positionManager_, address token0_, address token1_) {
        require(address(positionManager_) != address(0));
        positionManager = positionManager_;
        factory = IAlgebraFactory(positionManager.factory());

        token0 = token0_;
        token1 = token1_;

        pool = IAlgebraPool(factory.poolByPair(token0, token1));
    }

    /// @inheritdoc ICamelotHelper
    function calculateTvl(uint256 nft) public view returns (uint256[] memory tokenAmounts) {
        if (nft == 0) {
            return new uint256[](2);
        }
        (uint160 sqrtRatioX96, , , , , , ) = pool.globalState();
        tokenAmounts = new uint256[](2);
        (tokenAmounts[0], tokenAmounts[1]) = PositionValue.total(positionManager, nft, sqrtRatioX96);
    }

    /// @inheritdoc ICamelotHelper
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

    /// @inheritdoc ICamelotHelper
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

    /// @inheritdoc ICamelotHelper
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

    /// @inheritdoc ICamelotHelper
    function calculateLiquidityToPull(
        uint256 nft,
        uint160 sqrtRatioX96,
        uint256[] memory tokenAmounts
    ) public view returns (uint128 liquidity) {
        (, , , , , , uint128 positionLiquidity, , , , ) = positionManager.positions(nft);
        liquidity = tokenAmountsToMaxLiquidity(nft, sqrtRatioX96, tokenAmounts);
        liquidity = liquidity < positionLiquidity ? liquidity : positionLiquidity;
    }
}
