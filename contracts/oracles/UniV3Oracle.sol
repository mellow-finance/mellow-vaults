// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/IUniswapV3Factory.sol";
import "../interfaces/IOracle.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../libraries/CommonLibrary.sol";
import "../DefaultAccessControl.sol";

contract UniV3Oracle is DefaultAccessControl {
    IUniswapV3Factory public immutable factory;
    uint16 public observationsForAverage;

    constructor(
        IUniswapV3Factory factory_,
        uint16 observationsForAverage_,
        address admin
    ) DefaultAccessControl(admin) {
        factory = factory_;
        observationsForAverage = observationsForAverage_;
    }

    function prices(address token0, address token1) external view returns (uint256 spotPriceX96, uint256 avgPriceX96) {
        require(token1 > token0, ExceptionsLibrary.SORTED_AND_UNIQUE);
        address pool = factory.getPool(token0, token1, 3000);
        if (pool == address(0)) {
            pool = factory.getPool(token0, token1, 500);
        }
        if (pool == address(0)) {
            pool = factory.getPool(token0, token1, 10000);
        }
        require(pool != address(0), ExceptionsLibrary.UNISWAP_POOL_NOT_FOUND);

        (uint256 spotSqrtPriceX96, , uint16 observationIndex, uint16 observationCardinality, , , ) = IUniswapV3Pool(
            pool
        ).slot0();
        uint16 bfAvg = observationsForAverage;
        require(observationCardinality > bfAvg, ExceptionsLibrary.NOT_ENOUGH_CARDINALITY);
        uint256 obs1 = (uint256(observationIndex) + uint256(observationCardinality) - 1) %
            uint256(observationCardinality);
        uint256 obs0 = (uint256(observationIndex) + uint256(observationCardinality) - bfAvg) %
            uint256(observationCardinality);
        (uint32 timestamp0, int56 tick0, , ) = IUniswapV3Pool(pool).observations(obs0);
        (uint32 timestamp1, int56 tick1, , ) = IUniswapV3Pool(pool).observations(obs1);
        uint256 timespan = timestamp1 - timestamp0;
        int256 tickAverage = (int256(tick1) - int256(tick0)) / int256(uint256(timespan));
        uint256 avgSqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24(tickAverage));
        avgPriceX96 = FullMath.mulDiv(avgSqrtPriceX96, avgSqrtPriceX96, CommonLibrary.Q96);
        spotPriceX96 = FullMath.mulDiv(spotSqrtPriceX96, spotSqrtPriceX96, CommonLibrary.Q96);
    }

    function setObservationsForAverage(uint16 newObservationsForAverage) external {
        require(isAdmin(msg.sender), ExceptionsLibrary.ADMIN);
        require(observationsForAverage > 1, ExceptionsLibrary.INVALID_BLOCKS_FOR_AVERAGE);
        observationsForAverage = newObservationsForAverage;
        emit SetObservationsForAverage(tx.origin, msg.sender, newObservationsForAverage);
    }

    event SetObservationsForAverage(address indexed origin, address indexed sender, uint16 observationsForAverage);
}
