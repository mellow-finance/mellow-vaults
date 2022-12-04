// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../utils/UniswapV3Token.sol";
import "../utils/UniV3Helper.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/OracleLibrary.sol";
import "../interfaces/oracles/IChainlinkOracle.sol";

// import "../interfaces/vaults-v2/IVault.sol";

contract HStrategy {
    // expected functions

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

    function calculateExpectedRatios()
        public
        view
        returns (
            address[] memory erc20Tokens,
            uint256[] memory erc20TokensRatios,
            address[] memory uniV3Tokens,
            uint256[] memory uniV3TokensRatios
        )
    {
        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = uniswapToken.pool().slot0();
        // calculate current and expected ratios
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

        erc20Tokens = new address[](4);
        for (uint256 i = 0; i < 2; i++) {
            erc20Tokens[i] = address(depositTokens[i]);
            erc20Tokens[i + 2] = address(yieldTokens[i]);
        }

        erc20TokensRatios = new uint256[](4);
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
