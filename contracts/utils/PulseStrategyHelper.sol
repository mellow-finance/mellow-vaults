// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../strategies/PulseStrategy.sol";

contract PulseStrategyHelper {
    uint256 public constant Q96 = 2**96;

    function getStrategyParams(PulseStrategy strategy)
        public
        view
        returns (PulseStrategy.ImmutableParams memory immutableParams, PulseStrategy.MutableParams memory mutableParams)
    {
        {
            (address router, IERC20Vault erc20Vault, IUniV3Vault uniV3Vault) = strategy.immutableParams();
            immutableParams = PulseStrategy.ImmutableParams({
                router: router,
                erc20Vault: erc20Vault,
                uniV3Vault: uniV3Vault,
                tokens: erc20Vault.vaultTokens()
            });
        }
        {
            (
                int24 priceImpactD6,
                int24 intervalWidth,
                int24 tickNeighborhood,
                int24 maxDeviationForVaultPool,
                uint32 timespanForAverageTick,
                uint256 amount0Desired,
                uint256 amount1Desired,
                uint256 swapSlippageD,
                uint256 swappingAmountsCoefficientD
            ) = strategy.mutableParams();
            mutableParams = PulseStrategy.MutableParams({
                priceImpactD6: priceImpactD6,
                intervalWidth: intervalWidth,
                tickNeighborhood: tickNeighborhood,
                maxDeviationForVaultPool: maxDeviationForVaultPool,
                timespanForAverageTick: timespanForAverageTick,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                swapSlippageD: swapSlippageD,
                swappingAmountsCoefficientD: swappingAmountsCoefficientD,
                minSwapAmounts: new uint256[](2)
            });
        }
    }

    function calculateAmountForSwap(PulseStrategy strategy)
        public
        view
        returns (
            uint256 amount,
            address from,
            address to,
            IERC20Vault erc20Vault
        )
    {
        (
            PulseStrategy.ImmutableParams memory immutableParams,
            PulseStrategy.MutableParams memory mutableParams
        ) = getStrategyParams(strategy);

        IUniswapV3Pool pool = IUniswapV3Pool(immutableParams.uniV3Vault.pool());
        (uint160 sqrtPriceX96, int24 spotTick, , , , , ) = pool.slot0();
        uint256 targetRatioOfToken1;
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        {
            (PulseStrategy.Interval memory interval, ) = strategy.calculateNewPosition(
                mutableParams,
                spotTick,
                pool,
                immutableParams.uniV3Vault.uniV3Nft()
            );
            targetRatioOfToken1 = strategy.calculateTargetRatioOfToken1(interval, sqrtPriceX96, priceX96);
        }

        uint256 tokenInIndex;
        (tokenInIndex, amount) = strategy.calculateAmountsForSwap(
            immutableParams,
            mutableParams,
            priceX96,
            targetRatioOfToken1
        );

        from = immutableParams.tokens[tokenInIndex];
        to = immutableParams.tokens[tokenInIndex ^ 1];
        erc20Vault = immutableParams.erc20Vault;
    }
}
