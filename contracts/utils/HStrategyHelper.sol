// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../interfaces/vaults/IIntegrationVault.sol";
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
                domainPositionParams.domainLowerPriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.intervalPriceSqrtX96
            ) -
            FullMath.mulDiv(
                domainPositionParams.intervalPriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.domainUpperPriceSqrtX96
            );

        uint256 nominator0X96 = FullMath.mulDiv(
            domainPositionParams.intervalPriceSqrtX96,
            CommonLibrary.Q96,
            domainPositionParams.upperPriceSqrtX96
        ) -
            FullMath.mulDiv(
                domainPositionParams.intervalPriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.domainUpperPriceSqrtX96
            );

        uint256 nominator1X96 = FullMath.mulDiv(
            domainPositionParams.lowerPriceSqrtX96,
            CommonLibrary.Q96,
            domainPositionParams.intervalPriceSqrtX96
        ) -
            FullMath.mulDiv(
                domainPositionParams.domainLowerPriceSqrtX96,
                CommonLibrary.Q96,
                domainPositionParams.intervalPriceSqrtX96
            );

        ratios.token0RatioD = uint32(FullMath.mulDiv(nominator0X96, DENOMINATOR, denominatorX96));
        ratios.token1RatioD = uint32(FullMath.mulDiv(nominator1X96, DENOMINATOR, denominatorX96));

        ratios.uniV3RatioD = DENOMINATOR - ratios.token0RatioD - ratios.token1RatioD;
    }

    /// @notice calculates amount of missing tokens for uniV3 and money vaults
    /// @param moneyVault the strategy money vault
    /// @param expectedTokenAmounts the amount of tokens we expect after rebalance
    /// @param domainPositionParams current position and pool state combined with predictions from the oracle
    /// @param liquidity current liquidity in position
    /// @return missingTokenAmounts amounts of missing tokens
    function calculateMissingTokenAmounts(
        IIntegrationVault moneyVault,
        HStrategy.TokenAmounts memory expectedTokenAmounts,
        HStrategy.DomainPositionParams memory domainPositionParams,
        uint128 liquidity
    ) external view returns (HStrategy.TokenAmounts memory missingTokenAmounts) {
        // for uniV3Vault
        {
            uint256 token0Amount = 0;
            uint256 token1Amount = 0;
            (token0Amount, token1Amount) = LiquidityAmounts.getAmountsForLiquidity(
                domainPositionParams.intervalPriceSqrtX96,
                domainPositionParams.lowerPriceSqrtX96,
                domainPositionParams.upperPriceSqrtX96,
                liquidity
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
            (, uint256[] memory maxTvl) = moneyVault.tvl();
            uint256 token0Amount = maxTvl[0];
            uint256 token1Amount = maxTvl[1];

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
    /// @return tokenAmounts extra token amounts on UniV3Vault
    function calculateExtraTokenAmountsForUniV3Vault(
        HStrategy.TokenAmounts memory expectedTokenAmounts,
        HStrategy.DomainPositionParams memory domainPositionParams
    ) external pure returns (uint256[] memory tokenAmounts) {
        tokenAmounts = new uint256[](2);
        (tokenAmounts[0], tokenAmounts[1]) = LiquidityAmounts.getAmountsForLiquidity(
            domainPositionParams.intervalPriceSqrtX96,
            domainPositionParams.lowerPriceSqrtX96,
            domainPositionParams.upperPriceSqrtX96,
            domainPositionParams.liquidity
        );

        if (tokenAmounts[0] > expectedTokenAmounts.uniV3Token0) {
            tokenAmounts[0] -= expectedTokenAmounts.uniV3Token0;
        } else {
            tokenAmounts[0] = 0;
        }

        if (tokenAmounts[1] > expectedTokenAmounts.uniV3Token1) {
            tokenAmounts[1] -= expectedTokenAmounts.uniV3Token1;
        } else {
            tokenAmounts[1] = 0;
        }
    }

    /// @notice calculates extra tokens on money vault
    /// @param moneyVault the strategy money vault
    /// @param expectedTokenAmounts the amount of tokens we expect after rebalance
    /// @return tokenAmounts extra token amounts on MoneyVault
    function calculateExtraTokenAmountsForMoneyVault(
        IIntegrationVault moneyVault,
        HStrategy.TokenAmounts memory expectedTokenAmounts
    ) external view returns (uint256[] memory tokenAmounts) {
        (tokenAmounts, ) = moneyVault.tvl();

        if (tokenAmounts[0] > expectedTokenAmounts.moneyToken0) {
            tokenAmounts[0] -= expectedTokenAmounts.moneyToken0;
        } else {
            tokenAmounts[0] = 0;
        }

        if (tokenAmounts[1] > expectedTokenAmounts.moneyToken1) {
            tokenAmounts[1] -= expectedTokenAmounts.moneyToken1;
        } else {
            tokenAmounts[1] = 0;
        }
    }

    /// @notice calculates expected amounts of tokens after rebalance
    /// @param expectedRatios ratios of the capital on different assets
    /// @param expectedTokenAmountsInToken0 expected capitals (in token0) on the strategy vaults
    /// @param domainPositionParams current position and pool state combined with predictions from the oracle
    /// @param uniV3Helper helper for uniswap V3 calculations
    /// @return amounts amounts of tokens expected after rebalance on the strategy vaults
    function calculateExpectedTokenAmountsByExpectedRatios(
        HStrategy.ExpectedRatios memory expectedRatios,
        HStrategy.TokenAmountsInToken0 memory expectedTokenAmountsInToken0,
        HStrategy.DomainPositionParams memory domainPositionParams,
        UniV3Helper uniV3Helper
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

        (amounts.uniV3Token0, amounts.uniV3Token1) = uniV3Helper.getPositionTokenAmountsByCapitalOfToken0(
            domainPositionParams.lowerPriceSqrtX96,
            domainPositionParams.upperPriceSqrtX96,
            domainPositionParams.intervalPriceSqrtX96,
            domainPositionParams.spotPriceX96,
            expectedTokenAmountsInToken0.uniV3TokensAmountInToken0
        );
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
            params.intervalPriceSqrtX96,
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

    /// @notice calculates current capital of the strategy in token0
    /// @param params current position and pool state combined with predictions from the oracle
    /// @param currentTokenAmounts amounts of the tokens on the erc20 and money vaults
    /// @return capital total capital measured in token0
    function calculateCurrentCapitalInToken0(
        HStrategy.DomainPositionParams memory params,
        HStrategy.TokenAmounts memory currentTokenAmounts
    ) external pure returns (uint256 capital) {
        capital =
            currentTokenAmounts.erc20Token0 +
            FullMath.mulDiv(currentTokenAmounts.erc20Token1, CommonLibrary.Q96, params.spotPriceX96) +
            currentTokenAmounts.uniV3Token0 +
            FullMath.mulDiv(currentTokenAmounts.uniV3Token1, CommonLibrary.Q96, params.spotPriceX96) +
            currentTokenAmounts.moneyToken0 +
            FullMath.mulDiv(currentTokenAmounts.moneyToken1, CommonLibrary.Q96, params.spotPriceX96);
    }

    /// @notice calculates expected capitals on the vaults after rebalance
    /// @param totalCapitalInToken0 total capital in token0
    /// @param expectedRatios ratios of the capitals on the vaults expected after rebalance
    /// @param ratioParams_ ratio of the tokens between erc20 and money vault combined with needed deviations for rebalance to be called
    /// @return amounts capitals expected after rebalance measured in token0
    function calculateExpectedTokenAmountsInToken0(
        uint256 totalCapitalInToken0,
        HStrategy.ExpectedRatios memory expectedRatios,
        HStrategy.RatioParams memory ratioParams_
    ) external pure returns (HStrategy.TokenAmountsInToken0 memory amounts) {
        amounts.erc20TokensAmountInToken0 = FullMath.mulDiv(
            totalCapitalInToken0,
            ratioParams_.erc20CapitalRatioD,
            DENOMINATOR
        );
        amounts.uniV3TokensAmountInToken0 = FullMath.mulDiv(
            totalCapitalInToken0 - amounts.erc20TokensAmountInToken0,
            expectedRatios.uniV3RatioD,
            DENOMINATOR
        );
        amounts.moneyTokensAmountInToken0 =
            totalCapitalInToken0 -
            amounts.erc20TokensAmountInToken0 -
            amounts.uniV3TokensAmountInToken0;
        amounts.totalTokensInToken0 = totalCapitalInToken0;
    }

    /// @notice return true if the token swap is needed. It is needed if we cannot mint a new position without it
    /// @param currentTokenAmounts the amounts of tokens on the vaults
    /// @param expectedTokenAmounts the amounts of tokens expected after rebalancing
    /// @param ratioParams ratio of the tokens between erc20 and money vault combined with needed deviations for rebalance to be called
    /// @param domainPositionParams the current state of the position, pool and oracle prediction
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

        uint256 minToken0Deviation = FullMath.mulDiv(ratioParams.minCapitalDeviationD, totalToken0Amount, DENOMINATOR);
        uint256 minToken1Deviation = FullMath.mulDiv(ratioParams.minCapitalDeviationD, totalToken1Amount, DENOMINATOR);

        {
            if (
                currentTokenAmounts.erc20Token0 + minToken0Deviation < expectedTokenAmounts.erc20Token0 ||
                currentTokenAmounts.erc20Token0 > expectedTokenAmounts.erc20Token0 + minToken0Deviation ||
                currentTokenAmounts.erc20Token1 + minToken1Deviation < expectedTokenAmounts.erc20Token1 ||
                currentTokenAmounts.erc20Token1 > expectedTokenAmounts.erc20Token1 + minToken1Deviation
            ) {
                return true;
            }
        }

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

    /// @param tick current price tick
    /// @param strategyParams_ the current parameters of the strategy
    /// @param uniV3Nft the nft of the position from position manager
    /// @param positionManager_ the position manager for uniV3
    function calculateAndCheckDomainPositionParams(
        int24 tick,
        HStrategy.StrategyParams memory strategyParams_,
        uint256 uniV3Nft,
        INonfungiblePositionManager positionManager_
    ) external view returns (HStrategy.DomainPositionParams memory params) {
        (, , , , , int24 lowerTick, int24 upperTick, uint128 liquidity, , , , ) = positionManager_.positions(uniV3Nft);

        params = HStrategy.DomainPositionParams({
            nft: uniV3Nft,
            liquidity: liquidity,
            lowerTick: lowerTick,
            upperTick: upperTick,
            domainLowerTick: strategyParams_.domainLowerTick,
            domainUpperTick: strategyParams_.domainUpperTick,
            lowerPriceSqrtX96: TickMath.getSqrtRatioAtTick(lowerTick),
            upperPriceSqrtX96: TickMath.getSqrtRatioAtTick(upperTick),
            domainLowerPriceSqrtX96: TickMath.getSqrtRatioAtTick(strategyParams_.domainLowerTick),
            domainUpperPriceSqrtX96: TickMath.getSqrtRatioAtTick(strategyParams_.domainUpperTick),
            intervalPriceSqrtX96: TickMath.getSqrtRatioAtTick(tick),
            spotPriceX96: 0
        });
        params.spotPriceX96 = FullMath.mulDiv(
            params.intervalPriceSqrtX96,
            params.intervalPriceSqrtX96,
            CommonLibrary.Q96
        );
        if (params.intervalPriceSqrtX96 < params.lowerPriceSqrtX96) {
            params.intervalPriceSqrtX96 = params.lowerPriceSqrtX96;
        } else if (params.intervalPriceSqrtX96 > params.upperPriceSqrtX96) {
            params.intervalPriceSqrtX96 = params.upperPriceSqrtX96;
        }
    }

    /// @param tick current price tick
    /// @param pool_ address of uniV3 pool
    /// @param oracleParams_ oracle parameters
    /// @param uniV3Helper helper for uniswap V3 calculations
    function checkSpotTickDeviationFromAverage(
        int24 tick,
        address pool_,
        HStrategy.OracleParams memory oracleParams_,
        UniV3Helper uniV3Helper
    ) external view {
        (bool withFail, int24 deviation) = uniV3Helper.getTickDeviationForTimeSpan(
            tick,
            pool_,
            oracleParams_.averagePriceTimeSpan
        );
        require(!withFail, ExceptionsLibrary.INVALID_STATE);
        if (deviation < 0) {
            deviation = -deviation;
        }
        require(uint24(deviation) <= oracleParams_.maxTickDeviation, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    /// @param spotTick current price tick
    /// @param strategyParams_ parameters of strategy
    /// @return lowerTick lower tick of new position
    /// @return upperTick upper tick of new position
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

    /// @param currentTokenAmounts current token amounts on vaults in both tokens
    /// @param domainPositionParams the current state of the position, pool and oracle prediction
    /// @param hStrategyHelper_ address of HStrategyHelper
    /// @param uniV3Helper helper for uniswap V3 calculations
    /// @param ratioParams ratio parameters
    /// @return expectedTokenAmounts expected amounts of tokens after rebalance on vaults
    function calculateExpectedTokenAmounts(
        HStrategy.TokenAmounts memory currentTokenAmounts,
        HStrategy.DomainPositionParams memory domainPositionParams,
        HStrategyHelper hStrategyHelper_,
        UniV3Helper uniV3Helper,
        HStrategy.RatioParams memory ratioParams
    ) external pure returns (HStrategy.TokenAmounts memory expectedTokenAmounts) {
        HStrategy.ExpectedRatios memory expectedRatios = hStrategyHelper_.calculateExpectedRatios(domainPositionParams);
        uint256 currentCapitalInToken0 = hStrategyHelper_.calculateCurrentCapitalInToken0(
            domainPositionParams,
            currentTokenAmounts
        );
        HStrategy.TokenAmountsInToken0 memory expectedTokenAmountsInToken0 = hStrategyHelper_
            .calculateExpectedTokenAmountsInToken0(currentCapitalInToken0, expectedRatios, ratioParams);
        return
            hStrategyHelper_.calculateExpectedTokenAmountsByExpectedRatios(
                expectedRatios,
                expectedTokenAmountsInToken0,
                domainPositionParams,
                uniV3Helper
            );
    }
}
