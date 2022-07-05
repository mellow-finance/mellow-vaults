// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/vaults/IIntegrationVault.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../strategies/HStrategy.sol";
import "hardhat/console.sol";

contract HStrategyHelper {
    uint32 constant DENOMINATOR = 10**9;

    function calculateExpectedRatios(
        HStrategy.StrategyParams memory strategyParams_,
        HStrategy.DomainPositionParams memory domainPositionParams
    ) external pure returns (HStrategy.ExpectedRatios memory ratios) {
        if (strategyParams_.simulateUniV3Interval) {
            uint256 denominatorX96 = CommonLibrary.Q96 *
                2 -
                FullMath.mulDiv(
                    domainPositionParams.lower0PriceSqrtX96,
                    CommonLibrary.Q96,
                    domainPositionParams.averagePriceSqrtX96
                ) -
                FullMath.mulDiv(
                    domainPositionParams.averagePriceSqrtX96,
                    CommonLibrary.Q96,
                    domainPositionParams.upper0PriceSqrtX96
                );

            uint256 nominator0X96 = FullMath.mulDiv(
                domainPositionParams.averagePriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.upperPriceSqrtX96
            ) -
                FullMath.mulDiv(
                    domainPositionParams.averagePriceSqrtX96,
                    CommonLibrary.Q96,
                    domainPositionParams.upper0PriceSqrtX96
                );

            uint256 nominator1X96 = FullMath.mulDiv(
                domainPositionParams.lowerPriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.averagePriceSqrtX96
            ) -
                FullMath.mulDiv(
                    domainPositionParams.lower0PriceSqrtX96,
                    CommonLibrary.Q96,
                    domainPositionParams.averagePriceSqrtX96
                );

            ratios.token0RatioD = uint32(FullMath.mulDiv(nominator0X96, DENOMINATOR, denominatorX96));
            ratios.token1RatioD = uint32(FullMath.mulDiv(nominator1X96, DENOMINATOR, denominatorX96));
        } else {
            ratios.token0RatioD = uint32(
                FullMath.mulDiv(
                    domainPositionParams.averagePriceSqrtX96,
                    DENOMINATOR >> 1,
                    domainPositionParams.upperPriceSqrtX96
                )
            );
            ratios.token1RatioD = uint32(
                FullMath.mulDiv(
                    domainPositionParams.lowerPriceSqrtX96,
                    DENOMINATOR >> 1,
                    domainPositionParams.averagePriceSqrtX96
                )
            );
        }
        // remaining part goes to UniV3Vault
        ratios.uniV3RatioD = DENOMINATOR - ratios.token0RatioD - ratios.token1RatioD;
    }

    function calculateDomainPositionParams(
        int24 averageTick,
        uint160 sqrtSpotPriceX96,
        HStrategy.StrategyParams memory strategyParams_,
        uint256 uniV3Nft,
        INonfungiblePositionManager _positionManager
    ) external view returns (HStrategy.DomainPositionParams memory domainPositionParams) {
        (, , , , , int24 lowerTick, int24 upperTick, uint128 liquidity, , , , ) = _positionManager.positions(uniV3Nft);

        domainPositionParams = HStrategy.DomainPositionParams({
            nft: uniV3Nft,
            liquidity: liquidity,
            lowerTick: lowerTick,
            upperTick: upperTick,
            lower0Tick: strategyParams_.globalLowerTick,
            upper0Tick: strategyParams_.globalUpperTick,
            averageTick: averageTick,
            lowerPriceSqrtX96: TickMath.getSqrtRatioAtTick(lowerTick),
            upperPriceSqrtX96: TickMath.getSqrtRatioAtTick(upperTick),
            lower0PriceSqrtX96: TickMath.getSqrtRatioAtTick(strategyParams_.globalLowerTick),
            upper0PriceSqrtX96: TickMath.getSqrtRatioAtTick(strategyParams_.globalUpperTick),
            averagePriceSqrtX96: TickMath.getSqrtRatioAtTick(averageTick),
            averagePriceX96: 0,
            spotPriceSqrtX96: sqrtSpotPriceX96
        });
        domainPositionParams.averagePriceX96 = FullMath.mulDiv(
            domainPositionParams.averagePriceSqrtX96,
            domainPositionParams.averagePriceSqrtX96,
            CommonLibrary.Q96
        );
    }

    function calculateMissingTokenAmounts(
        IIntegrationVault moneyVault,
        HStrategy.TokenAmounts memory expectedTokenAmounts,
        HStrategy.DomainPositionParams memory domainPositionParams
    ) external view returns (HStrategy.TokenAmounts memory missingTokenAmounts) {
        // for uniV3Vault
        {
            uint256 token0Amount = 0;
            uint256 token1Amount = 0;
            (token0Amount, token1Amount) = LiquidityAmounts.getAmountsForLiquidity(
                domainPositionParams.spotPriceSqrtX96,
                domainPositionParams.lowerPriceSqrtX96,
                domainPositionParams.upperPriceSqrtX96,
                domainPositionParams.liquidity
            );

            if (token0Amount < expectedTokenAmounts.uniV3Token0) {
                missingTokenAmounts.uniV3Token0 = expectedTokenAmounts.uniV3Token0 - token0Amount;
            }
            if (token1Amount < expectedTokenAmounts.uniV3Token1) {
                missingTokenAmounts.uniV3Token1 = expectedTokenAmounts.uniV3Token1 - token1Amount;
            }
        }

        // for moneyVault
        {
            (uint256[] memory minTvl, uint256[] memory maxTvl) = moneyVault.tvl();
            uint256 token0Amount = (minTvl[0] + maxTvl[0]) >> 1;
            uint256 token1Amount = (minTvl[1] + maxTvl[1]) >> 1;

            if (token0Amount < expectedTokenAmounts.moneyToken0) {
                missingTokenAmounts.moneyToken0 = expectedTokenAmounts.moneyToken0 - token0Amount;
            }

            if (token1Amount < expectedTokenAmounts.moneyToken1) {
                missingTokenAmounts.moneyToken1 = expectedTokenAmounts.moneyToken1 - token1Amount;
            }
        }
    }

    function calculateExtraTokenAmountsForMoneyVault(
        IIntegrationVault moneyVault,
        HStrategy.TokenAmounts memory expectedTokenAmounts
    ) external view returns (uint256 token0Amount, uint256 token1Amount) {
        (uint256[] memory minTvl, uint256[] memory maxTvl) = moneyVault.tvl();
        token0Amount = (minTvl[0] + maxTvl[0]) >> 1;
        token1Amount = (minTvl[1] + maxTvl[1]) >> 1;

        if (token0Amount > expectedTokenAmounts.moneyToken0) {
            token0Amount -= expectedTokenAmounts.moneyToken0;
        } else {
            token0Amount = 0;
        }

        if (token1Amount > expectedTokenAmounts.moneyToken1) {
            token1Amount -= expectedTokenAmounts.moneyToken1;
        } else {
            token1Amount = 0;
        }
    }

    function calculateExpectedTokenAmounts(
        HStrategy.ExpectedRatios memory expectedRatios,
        HStrategy.TokenAmountsInToken0 memory expectedTokenAmountsInToken0,
        HStrategy.DomainPositionParams memory domainPositionParams
    ) external view returns (HStrategy.TokenAmounts memory amounts) {
        amounts.erc20Token0 = FullMath.mulDiv(
            expectedRatios.token0RatioD,
            expectedTokenAmountsInToken0.erc20TokensAmountInToken0,
            expectedRatios.token0RatioD + expectedRatios.token1RatioD
        );
        amounts.erc20Token1 = FullMath.mulDiv(
            expectedTokenAmountsInToken0.erc20TokensAmountInToken0 - amounts.erc20Token0,
            domainPositionParams.averagePriceX96,
            CommonLibrary.Q96
        );

        amounts.moneyToken0 = FullMath.mulDiv(
            expectedRatios.token0RatioD,
            expectedTokenAmountsInToken0.moneyTokensAmountInToken0,
            expectedRatios.token0RatioD + expectedRatios.token1RatioD
        );
        amounts.moneyToken1 = FullMath.mulDiv(
            expectedTokenAmountsInToken0.moneyTokensAmountInToken0 - amounts.moneyToken0,
            domainPositionParams.averagePriceX96,
            CommonLibrary.Q96
        );
        console.log(
            domainPositionParams.spotPriceSqrtX96,
            domainPositionParams.lowerPriceSqrtX96,
            domainPositionParams.upperPriceSqrtX96
        );
        {
            uint256 uniCapitalRatioX96 = FullMath.mulDiv(
                FullMath.mulDiv(
                    domainPositionParams.spotPriceSqrtX96 - domainPositionParams.lowerPriceSqrtX96,
                    CommonLibrary.Q96,
                    domainPositionParams.upperPriceSqrtX96 - domainPositionParams.spotPriceSqrtX96
                ),
                domainPositionParams.upperPriceSqrtX96,
                domainPositionParams.spotPriceSqrtX96
            );
            uint256 uniCapital1 = FullMath.mulDiv(
                expectedTokenAmountsInToken0.uniV3TokensAmountInToken0,
                uniCapitalRatioX96,
                uniCapitalRatioX96 + CommonLibrary.Q96
            );
            amounts.uniV3Token0 = expectedTokenAmountsInToken0.uniV3TokensAmountInToken0 - uniCapital1;
            uint256 spotPriceX96 = FullMath.mulDiv(
                domainPositionParams.spotPriceSqrtX96,
                domainPositionParams.spotPriceSqrtX96,
                CommonLibrary.Q96
            );
            amounts.uniV3Token1 = FullMath.mulDiv(uniCapital1, spotPriceX96, CommonLibrary.Q96);
        }
    }

    function calculateCurrentTokenAmounts(
        IIntegrationVault erc20Vault,
        IIntegrationVault moneyVault,
        HStrategy.DomainPositionParams memory params
    ) external view returns (HStrategy.TokenAmounts memory amounts) {
        (amounts.uniV3Token0, amounts.uniV3Token1) = LiquidityAmounts.getAmountsForLiquidity(
            params.spotPriceSqrtX96,
            params.lowerPriceSqrtX96,
            params.upperPriceSqrtX96,
            params.liquidity
        );

        {
            (uint256[] memory minMoneyTvl, uint256[] memory maxMoneyTvl) = moneyVault.tvl();
            amounts.moneyToken0 = (minMoneyTvl[0] + maxMoneyTvl[0]) >> 1;
            amounts.moneyToken1 = (minMoneyTvl[1] + maxMoneyTvl[1]) >> 1;
        }
        {
            (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
            amounts.erc20Token0 = erc20Tvl[0];
            amounts.erc20Token1 = erc20Tvl[1];
        }
    }

    function calculateCurrentTokenAmountsInToken0(
        HStrategy.DomainPositionParams memory params,
        HStrategy.TokenAmounts memory currentTokenAmounts
    ) external pure returns (HStrategy.TokenAmountsInToken0 memory amounts) {
        amounts.erc20TokensAmountInToken0 =
            currentTokenAmounts.erc20Token0 +
            FullMath.mulDiv(currentTokenAmounts.erc20Token1, CommonLibrary.Q96, params.averagePriceX96);
        amounts.uniV3TokensAmountInToken0 =
            currentTokenAmounts.uniV3Token0 +
            FullMath.mulDiv(currentTokenAmounts.uniV3Token1, CommonLibrary.Q96, params.averagePriceX96);
        amounts.moneyTokensAmountInToken0 =
            currentTokenAmounts.moneyToken0 +
            FullMath.mulDiv(currentTokenAmounts.moneyToken1, CommonLibrary.Q96, params.averagePriceX96);
        amounts.totalTokensInToken0 =
            amounts.erc20TokensAmountInToken0 +
            amounts.uniV3TokensAmountInToken0 +
            amounts.moneyTokensAmountInToken0;
    }

    function calculateExpectedTokenAmountsInToken0(
        HStrategy.TokenAmountsInToken0 memory currentTokenAmounts,
        HStrategy.ExpectedRatios memory expectedRatios,
        HStrategy.StrategyParams memory strategyParams_
    ) external pure returns (HStrategy.TokenAmountsInToken0 memory amounts) {
        amounts.uniV3TokensAmountInToken0 = FullMath.mulDiv(
            currentTokenAmounts.totalTokensInToken0,
            expectedRatios.uniV3RatioD,
            DENOMINATOR
        );
        amounts.totalTokensInToken0 = currentTokenAmounts.totalTokensInToken0;
        amounts.erc20TokensAmountInToken0 = FullMath.mulDiv(
            amounts.totalTokensInToken0 - amounts.uniV3TokensAmountInToken0,
            strategyParams_.erc20MoneyRatioD,
            DENOMINATOR
        );
        amounts.moneyTokensAmountInToken0 =
            amounts.totalTokensInToken0 -
            amounts.uniV3TokensAmountInToken0 -
            amounts.erc20TokensAmountInToken0;
    }
}
