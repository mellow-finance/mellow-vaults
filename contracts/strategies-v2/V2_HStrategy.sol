// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/UniswapV3Token.sol";
import "../utils/UniV3Helper.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/OracleLibrary.sol";
import "../interfaces/oracles/IChainlinkOracle.sol";

contract V2HStrategy {
    // check
    // startAuction
    // finishAuction
    // getCurrentRebalanceRestrictions

    uint256 constant Q96 = 2**96;
    uint256 constant DENOMINATOR = 10**9;

    IERC20[] public depositTokens;
    IERC20[] public yieldTokens;
    UniswapV3Token public uniswapToken;
    address public immutable vault;
    UniV3Helper public uniV3Helper;
    int24 public domainLowerTick;
    int24 public domainUpperTick;
    int24 public halfOfShortInterval;
    uint256 public erc20MoneyRatioD;

    constructor(address vault_) {
        vault = vault_;
    }

    function calculateNewShortTicks(int24 spotTick) public view returns (int24 lowerTick, int24 upperTick) {
        lowerTick = spotTick - (spotTick % halfOfShortInterval);
        upperTick = lowerTick + halfOfShortInterval;
        int24 centralTick = 0;
        if (spotTick - lowerTick <= upperTick - spotTick) {
            centralTick = lowerTick;
        } else {
            centralTick = upperTick;
        }
        int24 lowerBorder = domainLowerTick + halfOfShortInterval;
        if (centralTick < lowerBorder) {
            centralTick = lowerBorder;
        }
        int24 upperBorder = domainUpperTick - halfOfShortInterval;
        if (centralTick > upperBorder) {
            centralTick = upperBorder;
        }
        lowerTick = centralTick - halfOfShortInterval;
        upperTick = centralTick + halfOfShortInterval;
    }

    function calculateExpectedRatios() public view returns (IERC20[] memory tokens, uint256[] memory ratiosX96) {
        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = uniswapToken.pool().slot0();
        uint128 totalLiquidity = calculateTotalLiquidityByCapital(sqrtPriceX96);
        (int24 lowerTick, int24 upperTick) = calculateNewShortTicks(spotTick);

        uint256[] memory expectedUniV3Amounts = new uint256[](2);
        (expectedUniV3Amounts[0], expectedUniV3Amounts[1]) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            totalLiquidity
        );

        uint256[] memory expectedTotalAmounts = new uint256[](2);
        (expectedTotalAmounts[0], expectedTotalAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(domainLowerTick),
            TickMath.getSqrtRatioAtTick(domainUpperTick),
            totalLiquidity
        );

        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        uint256 capitalInToken0 = expectedTotalAmounts[0] + FullMath.mulDiv(expectedTotalAmounts[1], Q96, priceX96);
        uint256 uniCpitalInToken0 = expectedUniV3Amounts[0] + FullMath.mulDiv(expectedUniV3Amounts[1], Q96, priceX96);

        tokens = new IERC20[](5);
        ratiosX96 = new uint256[](5);

        tokens[0] = uniswapToken;
        ratiosX96[0] = FullMath.mulDiv(uniCpitalInToken0, Q96, capitalInToken0);

        tokens[1] = depositTokens[0];
        ratiosX96[1] = FullMath.mulDiv(
            FullMath.mulDiv(expectedTotalAmounts[0] - expectedUniV3Amounts[0], erc20MoneyRatioD, DENOMINATOR),
            Q96,
            capitalInToken0
        );

        tokens[2] = depositTokens[1];
        ratiosX96[2] = FullMath.mulDiv(
            FullMath.mulDiv(expectedTotalAmounts[1] - expectedUniV3Amounts[1], erc20MoneyRatioD, DENOMINATOR),
            Q96,
            capitalInToken0
        );

        tokens[3] = yieldTokens[0];
        ratiosX96[3] = FullMath.mulDiv(
            FullMath.mulDiv(
                expectedTotalAmounts[0] - expectedUniV3Amounts[0],
                DENOMINATOR - erc20MoneyRatioD,
                DENOMINATOR
            ),
            Q96,
            capitalInToken0
        );

        tokens[4] = yieldTokens[1];
        ratiosX96[4] = Q96 - ratiosX96[0] - ratiosX96[1] - ratiosX96[2] - ratiosX96[3];
    }

    function calculateTotalLiquidityByCapital(uint160 spotSqrtRatioX96) public view returns (uint128 liquidity) {
        uint160 lowerRatioX96 = TickMath.getSqrtRatioAtTick(domainLowerTick);
        uint160 upperRatioX96 = TickMath.getSqrtRatioAtTick(domainUpperTick);

        uint256 capital = 0;
        // call tvl function of vault to get all tokens and theirs amounts and convert all of that into one token
        uint256 priceX96 = FullMath.mulDiv(spotSqrtRatioX96, spotSqrtRatioX96, Q96);

        (uint256 amount0, uint256 amount1) = uniV3Helper.getPositionTokenAmountsByCapitalOfToken0(
            lowerRatioX96,
            upperRatioX96,
            spotSqrtRatioX96,
            priceX96,
            capital
        );
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            spotSqrtRatioX96,
            lowerRatioX96,
            upperRatioX96,
            amount0,
            amount1
        );
    }
}
