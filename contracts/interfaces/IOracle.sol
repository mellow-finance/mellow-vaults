// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVault.sol";

interface IOracle {
    /// @notice Gets the spot price for tokens
    /// @param token0 First token for the price
    /// @param token1 Second token for the price
    /// @return minPriceX96 Lower price estimation. The price is `token1 / token0`, i.e. how much token1 needed to buy one unit of token0. The price is in X96 format.
    /// @return maxPriceX96 Upper price estimation. The price is `token1 / token0`, i.e. how much token1 needed to buy one unit of token0. The price is in X96 format.
    function spotPrice(address token0, address token1) external view returns (uint256 minPriceX96, uint256 maxPriceX96);
}
