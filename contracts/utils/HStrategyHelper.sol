// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/vaults/IIntegrationVault.sol";
import "../interfaces/vaults/IUniV3Vault.sol";
import "../interfaces/vaults/IAaveVault.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/external/LiquidityAmounts.sol";
import "../strategies/HStrategy.sol";
import "./UniV3Helper.sol";

contract HStrategyHelper {
    uint32 constant DENOMINATOR = 10**9;

    /// @notice calculates the ratios of the capital on all vaults using price from the oracle
    /// @param domainPositionParams the current state of the position, pool and oracle prediction
    /// @return ratios ratios of the capital
    function calculateExpectedRatios(HStrategy.DomainPositionParams memory domainPositionParams)
        external
        pure
        returns (HStrategy.ExpectedRatios memory ratios)
    {
        uint256 denominatorX96 = CommonLibrary.Q96 *
            2 -
            FullMath.mulDiv(
                domainPositionParams.lower0PriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.spotPriceSqrtX96
            ) -
            FullMath.mulDiv(
                domainPositionParams.spotPriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.upper0PriceSqrtX96
            );

        uint256 nominator0X96 = FullMath.mulDiv(
            domainPositionParams.spotPriceSqrtX96,
            CommonLibrary.Q96,
            domainPositionParams.upperPriceSqrtX96
        ) -
            FullMath.mulDiv(
                domainPositionParams.spotPriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.upper0PriceSqrtX96
            );

        uint256 nominator1X96 = FullMath.mulDiv(
            domainPositionParams.lowerPriceSqrtX96,
            CommonLibrary.Q96,
            domainPositionParams.spotPriceSqrtX96
        ) -
            FullMath.mulDiv(
                domainPositionParams.lower0PriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.spotPriceSqrtX96
            );

        ratios.token0RatioD = uint32(FullMath.mulDiv(nominator0X96, DENOMINATOR, denominatorX96));
        ratios.token1RatioD = uint32(FullMath.mulDiv(nominator1X96, DENOMINATOR, denominatorX96));

        ratios.uniV3RatioD = DENOMINATOR - ratios.token0RatioD - ratios.token1RatioD;
    }

    /// @notice calculates the current state of the position and pool with given oracle predictions
    /// @param sqrtSpotPriceX96 square root of the spot price
    /// @param strategyParams_ parameters of the strategy
    /// @param uniV3Nft the current position nft from position manager
    /// @param _positionManager uniV3 position manager
    /// @return domainPositionParams current position and pool state combined with predictions from the oracle
    function calculateDomainPositionParams(
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
            lower0Tick: strategyParams_.domainLowerTick,
            upper0Tick: strategyParams_.domainUpperTick,
            lowerPriceSqrtX96: TickMath.getSqrtRatioAtTick(lowerTick),
            upperPriceSqrtX96: TickMath.getSqrtRatioAtTick(upperTick),
            lower0PriceSqrtX96: TickMath.getSqrtRatioAtTick(strategyParams_.domainLowerTick),
            upper0PriceSqrtX96: TickMath.getSqrtRatioAtTick(strategyParams_.domainUpperTick),
            spotPriceSqrtX96: sqrtSpotPriceX96,
            spotPriceX96: 0
        });
        domainPositionParams.spotPriceX96 = FullMath.mulDiv(sqrtSpotPriceX96, sqrtSpotPriceX96, CommonLibrary.Q96);
    }

    /// @notice calculates amount of missing tokens for uniV3 and money vaults
    /// @param moneyVault the strategy money vault
    /// @param expectedTokenAmounts the amount of tokens we expect after rebalance
    /// @param domainPositionParams current position and pool state combined with predictions from the oracle
    /// @return missingTokenAmounts amounts of missing tokens
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

    /// @notice calculates extra tokens on uniV3 vault
    /// @param expectedTokenAmounts the amount of tokens we expect after rebalance
    /// @param domainPositionParams current position and pool state combined with predictions from the oracle
    /// @return extraToken0Amount amount of token0 needed to be pulled from uniV3
    /// @return extraToken1Amount amount of token1 needed to be pulled from uniV3
    function calculateExtraTokenAmountsForUniV3Vault(
        HStrategy.TokenAmounts memory expectedTokenAmounts,
        HStrategy.DomainPositionParams memory domainPositionParams
    ) external pure returns (uint256 extraToken0Amount, uint256 extraToken1Amount) {
        (uint256 token0Amount, uint256 token1Amount) = LiquidityAmounts.getAmountsForLiquidity(
            domainPositionParams.spotPriceSqrtX96,
            domainPositionParams.lowerPriceSqrtX96,
            domainPositionParams.upperPriceSqrtX96,
            domainPositionParams.liquidity
        );

        if (expectedTokenAmounts.uniV3Token0 < token0Amount) {
            extraToken0Amount = token0Amount - expectedTokenAmounts.uniV3Token0;
        }
        if (expectedTokenAmounts.uniV3Token1 < token1Amount) {
            extraToken1Amount = token1Amount - expectedTokenAmounts.uniV3Token1;
        }
    }

    /// @notice calculates extra tokens on money vault
    /// @param moneyVault the strategy money vault
    /// @param expectedTokenAmounts the amount of tokens we expect after rebalance
    /// @return token0Amount amount of token0 needed to be pulled from uniV3
    /// @return token1Amount amount of token1 needed to be pulled from uniV3
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

    /// @notice calculates expected amounts of tokens after rebalance
    /// @param expectedRatios ratios of the capital on different assets
    /// @param expectedTokenAmountsInToken0 expected capitals (in token0) on the strategy vaults
    /// @param domainPositionParams current position and pool state combined with predictions from the oracle
    /// @return amounts amounts of tokens expected after rebalance on the strategy vaults
    function calculateExpectedTokenAmounts(
        HStrategy.ExpectedRatios memory expectedRatios,
        HStrategy.TokenAmountsInToken0 memory expectedTokenAmountsInToken0,
        HStrategy.DomainPositionParams memory domainPositionParams
    ) external pure returns (HStrategy.TokenAmounts memory amounts) {
        amounts.erc20Token0 = FullMath.mulDiv(
            expectedRatios.token0RatioD,
            expectedTokenAmountsInToken0.erc20TokensAmountInToken0,
            expectedRatios.token0RatioD + expectedRatios.token1RatioD
        );
        amounts.erc20Token1 = FullMath.mulDiv(
            expectedTokenAmountsInToken0.erc20TokensAmountInToken0 - amounts.erc20Token0,
            domainPositionParams.spotPriceX96,
            CommonLibrary.Q96
        );

        amounts.moneyToken0 = FullMath.mulDiv(
            expectedRatios.token0RatioD,
            expectedTokenAmountsInToken0.moneyTokensAmountInToken0,
            expectedRatios.token0RatioD + expectedRatios.token1RatioD
        );
        amounts.moneyToken1 = FullMath.mulDiv(
            expectedTokenAmountsInToken0.moneyTokensAmountInToken0 - amounts.moneyToken0,
            domainPositionParams.spotPriceX96,
            CommonLibrary.Q96
        );
        {
            uint256 uniCapital1;
            if (domainPositionParams.spotPriceSqrtX96 != domainPositionParams.upperPriceSqrtX96) {
                uint256 uniCapitalRatioX96 = FullMath.mulDiv(
                    FullMath.mulDiv(
                        domainPositionParams.spotPriceSqrtX96 - domainPositionParams.lowerPriceSqrtX96,
                        CommonLibrary.Q96,
                        domainPositionParams.upperPriceSqrtX96 - domainPositionParams.spotPriceSqrtX96
                    ),
                    domainPositionParams.upperPriceSqrtX96,
                    domainPositionParams.spotPriceSqrtX96
                );
                uniCapital1 = FullMath.mulDiv(
                    expectedTokenAmountsInToken0.uniV3TokensAmountInToken0,
                    uniCapitalRatioX96,
                    uniCapitalRatioX96 + CommonLibrary.Q96
                );
            } else {
                uniCapital1 = expectedTokenAmountsInToken0.uniV3TokensAmountInToken0;
            }
            amounts.uniV3Token0 = expectedTokenAmountsInToken0.uniV3TokensAmountInToken0 - uniCapital1;
            uint256 spotPriceX96 = FullMath.mulDiv(
                domainPositionParams.spotPriceSqrtX96,
                domainPositionParams.spotPriceSqrtX96,
                CommonLibrary.Q96
            );
            amounts.uniV3Token1 = FullMath.mulDiv(uniCapital1, spotPriceX96, CommonLibrary.Q96);
        }
    }

    /// @notice calculates current amounts of tokens
    /// @param erc20Vault the erc20 vault of the strategy
    /// @param moneyVault the money vault of the strategy
    /// @param params current position and pool state combined with predictions from the oracle
    /// @return amounts amounts of tokens
    function calculateCurrentTokenAmounts(
        IIntegrationVault erc20Vault,
        IIntegrationVault moneyVault,
        HStrategy.DomainPositionParams memory params
    ) external returns (HStrategy.TokenAmounts memory amounts) {
        (amounts.uniV3Token0, amounts.uniV3Token1) = LiquidityAmounts.getAmountsForLiquidity(
            params.spotPriceSqrtX96,
            params.lowerPriceSqrtX96,
            params.upperPriceSqrtX96,
            params.liquidity
        );

        {
            if (moneyVault.supportsInterface(type(IAaveVault).interfaceId)) {
                IAaveVault(address(moneyVault)).updateTvls();
            }
            (uint256[] memory minMoneyTvl, ) = moneyVault.tvl();
            amounts.moneyToken0 = minMoneyTvl[0];
            amounts.moneyToken1 = minMoneyTvl[1];
        }
        {
            (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
            amounts.erc20Token0 = erc20Tvl[0];
            amounts.erc20Token1 = erc20Tvl[1];
        }
    }

    /// @notice calculates current capitals on the vaults of the strategy (in token0)
    /// @param params current position and pool state combined with predictions from the oracle
    /// @param currentTokenAmounts amounts of the tokens on the erc20 and money vaults
    /// @return amounts capitals measured in token0
    function calculateCurrentTokenAmountsInToken0(
        HStrategy.DomainPositionParams memory params,
        HStrategy.TokenAmounts memory currentTokenAmounts
    ) external pure returns (HStrategy.TokenAmountsInToken0 memory amounts) {
        amounts.erc20TokensAmountInToken0 =
            currentTokenAmounts.erc20Token0 +
            FullMath.mulDiv(currentTokenAmounts.erc20Token1, CommonLibrary.Q96, params.spotPriceX96);
        amounts.uniV3TokensAmountInToken0 =
            currentTokenAmounts.uniV3Token0 +
            FullMath.mulDiv(currentTokenAmounts.uniV3Token1, CommonLibrary.Q96, params.spotPriceX96);
        amounts.moneyTokensAmountInToken0 =
            currentTokenAmounts.moneyToken0 +
            FullMath.mulDiv(currentTokenAmounts.moneyToken1, CommonLibrary.Q96, params.spotPriceX96);
        amounts.totalTokensInToken0 =
            amounts.erc20TokensAmountInToken0 +
            amounts.uniV3TokensAmountInToken0 +
            amounts.moneyTokensAmountInToken0;
    }

    /// @notice calculates expected capitals on the vaults after rebalance
    /// @param currentTokenAmounts current amount of tokens on the vaults
    /// @param expectedRatios ratios of the capitals on the vaults expected after rebalance
    /// @param ratioParams_ ratio of the tokens between erc20 and money vault combined with needed deviations for rebalance to be called
    /// @return amounts capitals expected after rebalance measured in token0
    function calculateExpectedTokenAmountsInToken0(
        HStrategy.TokenAmountsInToken0 memory currentTokenAmounts,
        HStrategy.ExpectedRatios memory expectedRatios,
        HStrategy.RatioParams memory ratioParams_
    ) external pure returns (HStrategy.TokenAmountsInToken0 memory amounts) {
        amounts.erc20TokensAmountInToken0 = FullMath.mulDiv(
            currentTokenAmounts.totalTokensInToken0,
            ratioParams_.erc20CapitalRatioD,
            DENOMINATOR
        );
        amounts.uniV3TokensAmountInToken0 = FullMath.mulDiv(
            currentTokenAmounts.totalTokensInToken0 - amounts.erc20TokensAmountInToken0,
            expectedRatios.uniV3RatioD,
            DENOMINATOR
        );
        amounts.moneyTokensAmountInToken0 =
            currentTokenAmounts.totalTokensInToken0 -
            amounts.erc20TokensAmountInToken0 -
            amounts.uniV3TokensAmountInToken0;
        amounts.totalTokensInToken0 = currentTokenAmounts.totalTokensInToken0;
    }

    /// @notice return true if the token swap is needed. It is needed if we cannot mint a new position without it
    /// @param currentTokenAmounts the amounts of tokens on the vaults
    /// @param expectedTokenAmounts the amounts of tokens expected after rebalancing
    /// @param ratioParams ratio of the tokens between erc20 and money vault combined with needed deviations for rebalance to be called
    /// @return needed true if the token swap is needed
    function swapNeeded(
        HStrategy.TokenAmounts memory currentTokenAmounts,
        HStrategy.TokenAmounts memory expectedTokenAmounts,
        HStrategy.RatioParams memory ratioParams,
        HStrategy.DomainPositionParams memory domainPositionParams
    ) external pure returns (bool needed) {
        uint256 expectedTotalToken0Amount = expectedTokenAmounts.erc20Token0 +
            expectedTokenAmounts.moneyToken0 +
            expectedTokenAmounts.uniV3Token0;
        uint256 expectedTotalToken1Amount = expectedTokenAmounts.erc20Token1 +
            expectedTokenAmounts.moneyToken1 +
            expectedTokenAmounts.uniV3Token1;

        uint256 currentTotalToken0Amount = currentTokenAmounts.erc20Token0 +
            currentTokenAmounts.moneyToken0 +
            currentTokenAmounts.uniV3Token0;
        int256 token0Delta = int256(currentTotalToken0Amount) - int256(expectedTotalToken0Amount);
        if (token0Delta < 0) {
            token0Delta = -token0Delta;
        }
        int256 minDeviation = int256(
            FullMath.mulDiv(
                expectedTotalToken0Amount +
                    FullMath.mulDiv(expectedTotalToken1Amount, CommonLibrary.Q96, domainPositionParams.spotPriceX96),
                ratioParams.minRebalanceDeviationD,
                DENOMINATOR
            )
        );
        return token0Delta >= minDeviation;
    }

    /// @notice returns true if the rebalance between assets on different vaults is needed
    /// @param currentTokenAmounts the current amounts of tokens on the vaults
    /// @param expectedTokenAmounts the amounts of tokens expected after rebalance
    /// @param ratioParams ratio of the tokens between erc20 and money vault combined with needed deviations for rebalance to be called
    /// @return needed true if the rebalance is needed
    function tokenRebalanceNeeded(
        HStrategy.TokenAmounts memory currentTokenAmounts,
        HStrategy.TokenAmounts memory expectedTokenAmounts,
        HStrategy.RatioParams memory ratioParams
    ) external pure returns (bool needed) {
        uint256 totalToken0Amount = expectedTokenAmounts.erc20Token0 +
            expectedTokenAmounts.moneyToken0 +
            expectedTokenAmounts.uniV3Token0;
        uint256 totalToken1Amount = expectedTokenAmounts.erc20Token1 +
            expectedTokenAmounts.moneyToken1 +
            expectedTokenAmounts.uniV3Token1;
        {
            uint256 erc20CapitalDeltaD = 0;
            if (ratioParams.erc20CapitalRatioD > ratioParams.minCaptialDeviationD) {
                erc20CapitalDeltaD = ratioParams.erc20CapitalRatioD - ratioParams.minCaptialDeviationD;
            }
            uint256 minToken0Amount = FullMath.mulDiv(erc20CapitalDeltaD, totalToken0Amount, DENOMINATOR);
            uint256 minToken1Amount = FullMath.mulDiv(erc20CapitalDeltaD, totalToken1Amount, DENOMINATOR);
            uint256 maxToken0Amount = FullMath.mulDiv(
                ratioParams.erc20CapitalRatioD + ratioParams.minCaptialDeviationD,
                totalToken0Amount,
                DENOMINATOR
            );
            uint256 maxToken1Amount = FullMath.mulDiv(
                ratioParams.erc20CapitalRatioD + ratioParams.minCaptialDeviationD,
                totalToken1Amount,
                DENOMINATOR
            );

            if (
                currentTokenAmounts.erc20Token0 < minToken0Amount ||
                currentTokenAmounts.erc20Token0 > maxToken0Amount ||
                currentTokenAmounts.erc20Token1 < minToken1Amount ||
                currentTokenAmounts.erc20Token1 > maxToken1Amount
            ) {
                return true;
            }
        }

        uint256 minToken0Deviation = FullMath.mulDiv(ratioParams.minCaptialDeviationD, totalToken0Amount, DENOMINATOR);
        uint256 minToken1Deviation = FullMath.mulDiv(ratioParams.minCaptialDeviationD, totalToken1Amount, DENOMINATOR);

        {
            if (
                currentTokenAmounts.moneyToken0 + minToken0Deviation < expectedTokenAmounts.moneyToken0 ||
                currentTokenAmounts.moneyToken0 > expectedTokenAmounts.moneyToken0 + minToken0Deviation ||
                currentTokenAmounts.moneyToken1 + minToken1Deviation < expectedTokenAmounts.moneyToken1 ||
                currentTokenAmounts.moneyToken1 > expectedTokenAmounts.moneyToken1 + minToken1Deviation
            ) {
                return true;
            }
        }

        {
            if (
                currentTokenAmounts.uniV3Token0 + minToken0Deviation < expectedTokenAmounts.uniV3Token0 ||
                currentTokenAmounts.uniV3Token0 > expectedTokenAmounts.uniV3Token0 + minToken0Deviation ||
                currentTokenAmounts.uniV3Token1 + minToken1Deviation < expectedTokenAmounts.uniV3Token1 ||
                currentTokenAmounts.uniV3Token1 > expectedTokenAmounts.uniV3Token1 + minToken1Deviation
            ) {
                return true;
            }
        }
    }

    function movePricesInDomainPosition(HStrategy.DomainPositionParams memory params)
        external
        pure
        returns (HStrategy.DomainPositionParams memory)
    {
        if (params.spotPriceSqrtX96 < params.lower0PriceSqrtX96) {
            params.spotPriceSqrtX96 = params.lower0PriceSqrtX96;
        } else if (params.spotPriceSqrtX96 > params.upper0PriceSqrtX96) {
            params.spotPriceSqrtX96 = params.upper0PriceSqrtX96;
        }
        params.spotPriceX96 = FullMath.mulDiv(params.spotPriceSqrtX96, params.spotPriceSqrtX96, CommonLibrary.Q96);
        return params;
    }

    /// @notice returns true if the rebalance between assets on different vaults is needed
    /// @param pool_ Uniswap V3 pool of the strategy
    /// @param hStrategyHelper_ the helper of the strategy
    /// @param strategyParams_ the current parameters of the strategy`
    /// @param uniV3Nft the nft of the position from position manager
    /// @param positionManager_ the position manager for uniV3
    function calculateAndCheckDomainPositionParams(
        IUniswapV3Pool pool_,
        HStrategyHelper hStrategyHelper_,
        HStrategy.StrategyParams memory strategyParams_,
        uint256 uniV3Nft,
        INonfungiblePositionManager positionManager_
    ) external view returns (HStrategy.DomainPositionParams memory domainPositionParams) {
        {
            (uint160 sqrtSpotPriceX96, , , , , , ) = pool_.slot0();
            domainPositionParams = hStrategyHelper_.calculateDomainPositionParams(
                sqrtSpotPriceX96,
                strategyParams_,
                uniV3Nft,
                positionManager_
            );
        }
        domainPositionParams = hStrategyHelper_.movePricesInDomainPosition(domainPositionParams);
    }

    function checkSpotTickDeviationFromAverage(
        IUniswapV3Pool pool_,
        HStrategy.OracleParams memory oracleParams_,
        UniV3Helper uniV3Helper
    ) external view {
        (bool withFail, int24 deviation) = uniV3Helper.getTickDeviationForTimeSpan(
            pool_,
            oracleParams_.averagePriceTimeSpan
        );
        require(!withFail, ExceptionsLibrary.INVALID_STATE);
        if (deviation < 0) {
            deviation = -deviation;
        }
        require(uint24(deviation) <= oracleParams_.maxTickDeviation, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    function calculateNewPositionTicks(int24 spotTick, HStrategy.StrategyParams memory strategyParams_)
        external
        pure
        returns (int24 lowerTick, int24 upperTick)
    {
        if (spotTick < strategyParams_.domainLowerTick) {
            spotTick = strategyParams_.domainLowerTick;
        } else if (spotTick > strategyParams_.domainUpperTick) {
            spotTick = strategyParams_.domainUpperTick;
        }

        int24 deltaToLowerTick = spotTick - strategyParams_.domainLowerTick;
        deltaToLowerTick -= (deltaToLowerTick % strategyParams_.halfOfShortInterval);
        int24 lowerEstimationCentralTick = strategyParams_.domainLowerTick + deltaToLowerTick;
        int24 upperEstimationCentralTick = lowerEstimationCentralTick + strategyParams_.halfOfShortInterval;
        int24 centralTick = 0;
        if (spotTick - lowerEstimationCentralTick <= upperEstimationCentralTick - spotTick) {
            centralTick = lowerEstimationCentralTick;
        } else {
            centralTick = upperEstimationCentralTick;
        }

        lowerTick = centralTick - strategyParams_.halfOfShortInterval;
        upperTick = centralTick + strategyParams_.halfOfShortInterval;

        if (lowerTick < strategyParams_.domainLowerTick) {
            lowerTick = strategyParams_.domainLowerTick;
            upperTick = lowerTick + (strategyParams_.halfOfShortInterval << 1);
        } else if (upperTick > strategyParams_.domainUpperTick) {
            upperTick = strategyParams_.domainUpperTick;
            lowerTick = upperTick - (strategyParams_.halfOfShortInterval << 1);
        }
    }
}
