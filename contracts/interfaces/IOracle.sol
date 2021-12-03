// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVault.sol";

interface IOracle {
    /// @notice Gets the spot price for tokens
    /// @param oracle Oracle number (i.e. which oracle to use)
    /// @param token0 First token for the price
    /// @param token1 Second token for the price
    /// @return priceX96 The price `token1 / token0`, i.e. how much token1 needed to buy one unit of token0. The price is in X96 format.
    function spotPrice(
        uint256 oracle,
        address token0,
        address token1
    ) external view returns (uint256 priceX96);

    /// @notice Gets the average price for tokens
    /// @param oracle Oracle number (i.e. which oracle to use)
    /// @param token0 First token for the price
    /// @param token1 Second token for the price
    /// @return priceX96 The price `token1 / token0`, i.e. how much token1 needed to buy one unit of token0. The price is in X96 format.
    /// @return actualTimespan The actual timespan for average
    function averagePrice(
        uint256 oracle,
        address token0,
        address token1,
        uint256 minTimespan
    ) external view returns (uint256 priceX96, uint256 actualTimespan);
}
