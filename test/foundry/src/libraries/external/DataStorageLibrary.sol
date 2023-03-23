// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../../interfaces/external/quickswap/IAlgebraPool.sol";

/// @title DataStorage library
/// @notice Provides functions to integrate with pool dataStorage
library DataStorageLibrary {
    /// @notice Fetches time-weighted average tick using Algebra dataStorage
    /// @param pool Address of Algebra pool that we want to getTimepoints
    /// @param period Number of seconds in the past to start calculating time-weighted average
    /// @return arithmeticMeanTick The time-weighted average tick from (block.timestamp - period) to block.timestamp
    /// @return withFail Flag that true if function observe of IUniswapV3Pool reverts with some error
    function consult(address pool, uint32 period) internal view returns (int24 arithmeticMeanTick, bool withFail) {
        require(period != 0, "BP");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = period;
        secondsAgos[1] = 0;
        unchecked {
            try IAlgebraPool(pool).getTimepoints(secondsAgos) returns (
                int56[] memory tickCumulatives,
                uint160[] memory,
                uint112[] memory,
                uint256[] memory
            ) {
                int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

                arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(period)));

                // Always round to negative infinity
                if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(period)) != 0)) arithmeticMeanTick--;
            } catch {
                return (0, true);
            }
        }
    }
}
