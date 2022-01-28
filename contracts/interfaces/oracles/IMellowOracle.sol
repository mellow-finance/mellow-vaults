// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IMellowOracle {
    /// @notice Gets the spot price for tokens
    /// @dev Out of each suboracle (univ2, chainlink) it extracts spot price. Out of univ3 it extracts spotPrice and average price for
    /// the last n blocks (excluding current block). Then all this values are combined, minPrice is minimum value, maxPrice is maximum
    /// value price is average of these values. It is highly recommended to use this oracle with setting Chainlink + Univ3 or Chainlink + Univ3 + UniV2. All other combinations
    /// might be unsafe and should be used only for dev / test purposes.
    /// @param token0 First token for the price
    /// @param token1 Second token for the price
    /// @return priceX96 Price estimation. The price is `token1 / token0`, i.e. how much token1 needed to buy one unit of token0. The price is in X96 format.
    /// @return minPriceX96 Lower price estimation. The price is `token1 / token0`, i.e. how much token1 needed to buy one unit of token0. The price is in X96 format.
    /// @return maxPriceX96 Upper price estimation. The price is `token1 / token0`, i.e. how much token1 needed to buy one unit of token0. The price is in X96 format.
    function spotPriceX96(address token0, address token1)
        external
        view
        returns (
            uint256 priceX96,
            uint256 minPriceX96,
            uint256 maxPriceX96
        );
}
