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

    uint256 public constant Q96 = 2**96;
    uint256 public constant DENOMINATOR = 10**9;

    uint24 public immutable fee;
    address public immutable token0;
    address public immutable token1;

    address public immutable yieldToken0;
    address public immutable yieldToken1;
    UniswapV3Token[] public uniswapTokens;
    uint256 public immutable positionsCount;
    address public immutable vault;

    IUniswapV3Pool public immutable pool;
    INonfungiblePositionManager public immutable positionManager;
    UniV3Helper public uniV3Helper;

    int24 public domainLowerTick;
    int24 public domainUpperTick;
    int24 public halfOfShortInterval;
    uint256 public erc20MoneyRatioD;
    uint256 public maxDeviationX96;

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

        // may be we need to make a common factory and create
        // this tokens using this factory
        for (
            int24 tick = domainLowerTick;
            tick + 2 * halfOfShortInterval <= domainUpperTick;
            tick += halfOfShortInterval
        ) {
            uniswapTokens.push(
                new UniswapV3Token(positionManager, token0, token1, tick, tick + halfOfShortInterval * 2, fee)
            );
        }
        positionsCount = uniswapTokens.length;
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

        {
            int24 lowerBorder = domainLowerTick + halfOfShortInterval;
            if (centralTick < lowerBorder) {
                centralTick = lowerBorder;
            } else {
                int24 upperBorder = domainUpperTick - halfOfShortInterval;
                if (centralTick > upperBorder) {
                    centralTick = upperBorder;
                }
            }
        }

        lowerTick = centralTick - halfOfShortInterval;
        upperTick = centralTick + halfOfShortInterval;
        uniswapTokenIndex = uint256(int256((lowerTick - domainLowerTick) / halfOfShortInterval));
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

        tokens = new address[](4 + positionsCount);
        ratiosX96 = new uint256[](4 + positionsCount);

        for (uint256 i = 0; i < positionsCount; i++) {
            tokens[i] = address(uniswapTokens[i]);
        }

        ratiosX96[uniswapTokenIndex] = FullMath.mulDiv(uniCpitalInToken0, Q96, capitalInToken0);

        tokens[positionsCount] = token0;
        ratiosX96[positionsCount] = FullMath.mulDiv(
            FullMath.mulDiv(expectedTotalAmounts[0] - expectedUniV3Amounts[0], erc20MoneyRatioD, DENOMINATOR),
            Q96,
            capitalInToken0
        );

        tokens[positionsCount + 1] = token1;
        ratiosX96[positionsCount + 1] = FullMath.mulDiv(
            FullMath.mulDiv(expectedTotalAmounts[1] - expectedUniV3Amounts[1], erc20MoneyRatioD, DENOMINATOR),
            Q96,
            capitalInToken0
        );

        tokens[positionsCount + 2] = yieldToken0;
        ratiosX96[positionsCount + 2] = FullMath.mulDiv(
            FullMath.mulDiv(
                expectedTotalAmounts[0] - expectedUniV3Amounts[0],
                DENOMINATOR - erc20MoneyRatioD,
                DENOMINATOR
            ),
            Q96,
            capitalInToken0
        );

        tokens[positionsCount + 3] = yieldToken1;
        ratiosX96[positionsCount + 3] = Q96 - ratiosX96[0] - ratiosX96[1] - ratiosX96[2] - ratiosX96[3];
    }

    function calculateCurrentRatios() public view returns (address[] memory tokens, uint256[] memory ratiosX96) {
        tokens = new address[](4 + positionsCount);
        ratiosX96 = new uint256[](4 + positionsCount);
        uint256 capitalInToken0 = getCapitalInToken0();
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        for (uint256 i = 0; i < positionsCount; i++) {
            tokens[i] = address(uniswapTokens[i]);
            uint128 liquidity = uint128(uniswapTokens[i].balanceOf(address(this)));
            (uint256 amount0, uint256 amount1) = uniswapTokens[i].liquidityToTokenAmounts(liquidity);
            ratiosX96[i] = FullMath.mulDiv(amount0 + FullMath.mulDiv(amount1, Q96, priceX96), Q96, capitalInToken0);
        }

        tokens[positionsCount] = token0;
        ratiosX96[positionsCount] = FullMath.mulDiv(IERC20(token0).balanceOf(address(this)), Q96, capitalInToken0);
        tokens[positionsCount + 1] = token1;
        ratiosX96[positionsCount + 1] = FullMath.mulDiv(
            FullMath.mulDiv(IERC20(token1).balanceOf(address(this)), Q96, priceX96),
            Q96,
            capitalInToken0
        );

        tokens[positionsCount + 2] = yieldToken0;
        ratiosX96[positionsCount + 2] = FullMath.mulDiv(
            IERC20(yieldToken0).balanceOf(address(this)), // convert to token0 with converter
            Q96,
            capitalInToken0
        );
        tokens[positionsCount + 3] = yieldToken1;
        ratiosX96[positionsCount + 3] = FullMath.mulDiv(
            FullMath.mulDiv(IERC20(yieldToken1).balanceOf(address(this)), Q96, priceX96), // convert to token1 with converter
            Q96,
            capitalInToken0
        );
    }

    function startAuction() public {
        (address[] memory currentTokens, uint256[] memory currentRatios) = calculateCurrentRatios();
        (, uint256[] memory expectedRatios) = calculateCurrentRatios();
        for (uint256 i = 0; i < currentTokens.length; i++) {
            uint256 currentRatioX96 = currentRatios[i];
            uint256 expectedRatioX96 = expectedRatios[i];
            if (
                expectedRatioX96 + maxDeviationX96 < currentRatioX96 ||
                currentRatioX96 + maxDeviationX96 < expectedRatioX96
            ) {
                // vault.startAuction();
            }
        }
    }

    function stopAuction() public {
        (address[] memory currentTokens, uint256[] memory currentRatios) = calculateCurrentRatios();
        (, uint256[] memory expectedRatios) = calculateCurrentRatios();
        for (uint256 i = 0; i < currentTokens.length; i++) {
            uint256 currentRatioX96 = currentRatios[i];
            uint256 expectedRatioX96 = expectedRatios[i];
            if (
                expectedRatioX96 + maxDeviationX96 < currentRatioX96 ||
                currentRatioX96 + maxDeviationX96 < expectedRatioX96
            ) {
                revert(ExceptionsLibrary.INVALID_STATE);
            }
        }
        // vault.stopAuction();
    }

    function getCapitalInToken0() public view returns (uint256 capitalInToken0) {
        uint256 totalAmount0 = IERC20(token0).balanceOf(address(this));
        uint256 totalAmount1 = IERC20(token1).balanceOf(address(this));
        for (uint256 i = 0; i < positionsCount; i++) {
            uint128 liquidity = uint128(uniswapTokens[i].balanceOf(address(this)));
            (uint256 amount0, uint256 amount1) = uniswapTokens[i].liquidityToTokenAmounts(liquidity);
            totalAmount0 += amount0;
            totalAmount1 += amount1;
        }

        // TODO: add converter
        // totalAmount0 += converter.convert(yieldToken0, token0, IERC20(yieldToken0).balanceOf(address(this)));
        // totalAmount1 += converter.convert(yieldToken1, token1, IERC20(yieldToken1).balanceOf(address(this)));

        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, Q96);

        capitalInToken0 = totalAmount0 + FullMath.mulDiv(totalAmount1, Q96, priceX96);
    }

    function calculateTotalLiquidityByCapital(uint160 spotSqrtRatioX96) public view returns (uint128 liquidity) {
        uint160 lowerRatioX96 = TickMath.getSqrtRatioAtTick(domainLowerTick);
        uint160 upperRatioX96 = TickMath.getSqrtRatioAtTick(domainUpperTick);
        uint256 priceX96 = FullMath.mulDiv(spotSqrtRatioX96, spotSqrtRatioX96, Q96);
        // mb we need to call here vault `tvl` function
        uint256 capital = getCapitalInToken0();

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
