// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/OracleLibrary.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";
import "../strategies/DeltaNeutralStrategyBob.sol";

contract DeltaNeutralHelper {
    DeltaNeutralStrategyBob public strategy;
    INonfungiblePositionManager public manager;
    IUniswapV3Factory public factory;

    uint32 averagePriceTimeSpan;
    uint24 maxTickDeviation;

    constructor(
        DeltaNeutralStrategyBob strategy_,
        INonfungiblePositionManager manager_,
        IUniswapV3Factory factory_
    ) {
        strategy = strategy_;
        manager = manager_;
        factory = factory_;
    }

    function areDeltasOkay(
        bool createNewPosition,
        int24 tickLower,
        int24 tickUpper,
        uint256 nft
    )
        public
        returns (
            bool,
            int24,
            int24,
            int24
        )
    {
        int24 spotTickR;

        (averagePriceTimeSpan, maxTickDeviation) = strategy.oracleParams();
        IUniswapV3Pool pool = strategy.pool();

        for (uint256 i = 0; i < 3; ++i) {
            for (uint256 j = i + 1; j < 3; ++j) {
                IUniswapV3Pool poolIJ;

                {
                    (uint24 swapFee, ) = strategy.swapParams(i, j);
                    poolIJ = IUniswapV3Pool(factory.getPool(strategy.tokens(i), strategy.tokens(j), swapFee));
                }

                (, int24 spotTick, , , , , ) = poolIJ.slot0();

                if (address(poolIJ) == address(pool) && nft != 0 && !createNewPosition) {
                    (, , , , , tickLower, tickUpper, , , , , ) = manager.positions(nft);
                    require(tickLower < spotTick && spotTick < tickUpper, ExceptionsLibrary.INVARIANT);
                }

                int24 avgTick;

                {
                    bool withFail;
                    (avgTick, , withFail) = OracleLibrary.consult(address(poolIJ), averagePriceTimeSpan);
                    require(!withFail, ExceptionsLibrary.INVALID_STATE);
                }

                if (spotTick < avgTick && avgTick - spotTick > int24(maxTickDeviation)) {
                    return (false, spotTick, tickLower, tickUpper);
                }

                if (avgTick < spotTick && spotTick - avgTick > int24(maxTickDeviation)) {
                    return (false, spotTick, tickLower, tickUpper);
                }

                if (address(poolIJ) == address(pool)) {
                    spotTickR = spotTick;
                }
            }
        }

        return (true, spotTickR, tickLower, tickUpper);
    }
}
