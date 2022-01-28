// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../external/univ3/IUniswapV3Factory.sol";

interface IUniV3Oracle {
    /// @notice Reference to UniV3 factory
    function factory() external returns (IUniswapV3Factory);

    /// @notice Number of observations for average price
    function observationsForAverage() external returns (uint16);

    /// @notice UniV3 prices for a token pair
    /// @dev Tokens must be sorted (token 1 > token0). Throws if univ3 pool doesn't exist or there's no data to fulfill
    /// observationsForAverage requirement.
    /// @param token0 Token 0 for price
    /// @param token1 Token 1 for price
    /// @return spotPriceX96 Current UniV3 price
    /// @return avgPriceX96 Average UniV3 price in the observation range [-observationsForAverage, -1]. Calculated by averaging ticks and then calculating price.
    function pricesX96(address token0, address token1) external view returns (uint256 spotPriceX96, uint256 avgPriceX96);

    /// @notice Update number of observations for average price
    /// @param newObservationsForAverage New value for observations
    function setObservationsForAverage(uint16 newObservationsForAverage) external;
}
