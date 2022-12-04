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

    uint24 public immutable fee;
    address public immutable token0;
    address public immutable token1;

    address public immutable yieldToken0;
    address public immutable yieldToken1;
    UniswapV3Token[] public uniswapTokens;
    address public immutable vault;

    IUniswapV3Pool public immutable pool;
    INonfungiblePositionManager public immutable positionManager;
    UniV3Helper public uniV3Helper;

    int24 public domainLowerTick;
    int24 public domainUpperTick;
    int24 public halfOfShortInterval;
    uint256 public erc20MoneyRatioD;

    constructor(
        address vault_,
        int24 domainLowerTick_,
        int24 domainUpperTick_,
        int24 halfOfShortInterval_,
        uint256 erc20MoneyRatioD_,
        UniV3Helper uniV3Helper_,
        address token0_,
        address token1_,
        address yieldToken0_,
        address yieldToken1_,
        uint24 fee_,
        INonfungiblePositionManager positionManager_
    ) {
        vault = vault_;
        uniV3Helper = uniV3Helper_;
        domainLowerTick = domainLowerTick_;
        domainUpperTick = domainUpperTick_;
        halfOfShortInterval = halfOfShortInterval_;
        erc20MoneyRatioD = erc20MoneyRatioD_;

        token0 = token0_;
        token1 = token1_;
        yieldToken0 = yieldToken0_;
        yieldToken1 = yieldToken1_;
        fee = fee_;
        positionManager = positionManager_;
        pool = IUniswapV3Pool(IUniswapV3Factory(positionManager.factory()).getPool(token0, token1, fee));
        uint256 uniswapPositionsCount = (uint256(int256((domainUpperTick - domainLowerTick) / halfOfShortInterval)) +
            1) / 2;
        // may be we need to make a common factory and create
        // this tokens using this factory
        uniswapTokens = new UniswapV3Token[](uniswapPositionsCount);

        // INonfungiblePositionManager positionManager_,
        // address token0_,
        // address token1_,
        // int24 tickLower_,
        // int24 tickUpper_,
        // uint24 fee_
        uint256 index = 0;
        for (
            int24 tick = domainLowerTick;
            tick + 2 * halfOfShortInterval <= domainUpperTick;
            tick += halfOfShortInterval
        ) {
            uniswapTokens[index] = new UniswapV3Token(
                positionManager,
                token0,
                token1,
                tick,
                tick + halfOfShortInterval * 2,
                fee
            );
            ++index;
        }
    }

    function getUniswapTokenIndex(int24 spotTick) public view returns (uint256 uniswapTokenIndex) {
        int24 lowerTick = spotTick - (spotTick % halfOfShortInterval);
        int24 upperTick = lowerTick + halfOfShortInterval;
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
        uniswapTokenIndex = type(uint256).max;
        for (uint256 i = 0; i < uniswapTokens.length; i++) {
            if (uniswapTokens[i].tickLower() == lowerTick && uniswapTokens[i].tickUpper() == upperTick) {
                uniswapTokenIndex = i;
            }
        }
        if (uniswapTokenIndex == type(uint256).max) {
            revert(ExceptionsLibrary.INVALID_STATE);
        }
    }

    function calculateExpectedRatios() public view returns (address[] memory tokens, uint256[] memory ratiosX96) {
        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = pool.slot0();
        uint128 totalLiquidity = calculateTotalLiquidityByCapital(sqrtPriceX96);
        uint256 uniswapTokenIndex = getUniswapTokenIndex(spotTick);

        uint256[] memory expectedUniV3Amounts = new uint256[](2);

        UniswapV3Token uniswapToken = uniswapTokens[uniswapTokenIndex];
        (expectedUniV3Amounts[0], expectedUniV3Amounts[1]) = uniswapToken.liquidityToTokenAmounts(totalLiquidity);

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

        tokens = new address[](5);
        ratiosX96 = new uint256[](5);

        tokens[0] = address(uniswapToken);
        ratiosX96[0] = FullMath.mulDiv(uniCpitalInToken0, Q96, capitalInToken0);

        tokens[1] = token0;
        ratiosX96[1] = FullMath.mulDiv(
            FullMath.mulDiv(expectedTotalAmounts[0] - expectedUniV3Amounts[0], erc20MoneyRatioD, DENOMINATOR),
            Q96,
            capitalInToken0
        );

        tokens[2] = token1;
        ratiosX96[2] = FullMath.mulDiv(
            FullMath.mulDiv(expectedTotalAmounts[1] - expectedUniV3Amounts[1], erc20MoneyRatioD, DENOMINATOR),
            Q96,
            capitalInToken0
        );

        tokens[3] = yieldToken0;
        ratiosX96[3] = FullMath.mulDiv(
            FullMath.mulDiv(
                expectedTotalAmounts[0] - expectedUniV3Amounts[0],
                DENOMINATOR - erc20MoneyRatioD,
                DENOMINATOR
            ),
            Q96,
            capitalInToken0
        );

        tokens[4] = yieldToken1;
        ratiosX96[4] = Q96 - ratiosX96[0] - ratiosX96[1] - ratiosX96[2] - ratiosX96[3];
    }

    function calculateTotalLiquidityByCapital(uint160 spotSqrtRatioX96) public view returns (uint128 liquidity) {
        uint160 lowerRatioX96 = TickMath.getSqrtRatioAtTick(domainLowerTick);
        uint160 upperRatioX96 = TickMath.getSqrtRatioAtTick(domainUpperTick);
        uint256 priceX96 = FullMath.mulDiv(spotSqrtRatioX96, spotSqrtRatioX96, Q96);
        // mb we need to call here vault `tvl` function
        uint256 capital = calculateStrategyCapital(priceX96);

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

    function calculateStrategyCapital(uint256 priceX96) public view returns (uint256 capital) {
        uint256 totalAmount0 = IERC20(token0).balanceOf(address(this));
        uint256 totalAmount1 = IERC20(token1).balanceOf(address(this));
        for (uint256 i = 0; i < uniswapTokens.length; i++) {
            UniswapV3Token token = uniswapTokens[i];
            uint256 liquidity = token.balanceOf(address(this));
            (uint256 amount0, uint256 amount1) = token.liquidityToTokenAmounts(uint128(liquidity));
            totalAmount0 += amount0;
            totalAmount1 += amount1;
        }

        // convert yield tokens to deposit tokens. Probably we could use a global converter of tokens for yield tokens like aave or yearn
        // totalAmount0 += converter.convert(from: yieldToken0, to: token0, amount: yieldToken0.balanceOf(address(this)))
        // totalAmount1 += converter.convert(yieldToken1, token1, yieldToken1.balanceOf(address(this)))
        capital = totalAmount0 + FullMath.mulDiv(totalAmount1, Q96, priceX96);
    }
}
