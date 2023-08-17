// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../libraries/ExceptionsLibrary.sol";
import "../libraries/external/OracleLibrary.sol";
import "../libraries/external/DataStorageLibrary.sol";

contract SinglePositionStrategyHelper {
    function checkUniV3PoolState(
        address pool,
        int24 maxDeviation,
        uint32 timespan
    ) public view {
        (, int24 spotTick, , , , , ) = IUniswapV3Pool(pool).slot0();
        (int24 averageTick, , bool withFail) = OracleLibrary.consult(pool, timespan);
        require(!withFail, ExceptionsLibrary.INVALID_STATE);
        int24 tickDeviation = spotTick - averageTick;
        if (tickDeviation < 0) {
            tickDeviation = -tickDeviation;
        }
        require(tickDeviation < maxDeviation, ExceptionsLibrary.LIMIT_OVERFLOW);
    }

    function checkAlgebraPoolState(
        address pool,
        int24 maxDeviation,
        uint32 timespan
    ) public view {
        (, int24 spotTick, , , , , ) = IAlgebraPool(pool).globalState();
        (int24 averageTick, bool withFail) = DataStorageLibrary.consult(pool, timespan);
        require(!withFail, ExceptionsLibrary.INVALID_STATE);
        int24 tickDeviation = spotTick - averageTick;
        if (tickDeviation < 0) {
            tickDeviation = -tickDeviation;
        }
        require(tickDeviation < maxDeviation, ExceptionsLibrary.LIMIT_OVERFLOW);
    }
}
