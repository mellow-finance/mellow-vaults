// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IOracle {
    /// @notice Oracle price for tokens.
    /// @dev The price is token1 / token0 i.e. how many weis of token1 required for 1 wei of token0.
    /// The safety indexes are:
    ///
    /// 1 - unsafe, this is typically a spot price that can be easily manipulated,
    ///
    /// 2 - 4 - more or less safe, this is typically a uniV3 oracle, where the safety is defined by the timespan of the average price
    ///
    /// 5 - safe - this is typically a chailink oracle
    /// @param token0 Reference to token0
    /// @param token1 Reference to token1
    /// @param minSafetyIndex Mimimal safety of the oracle, all observations with lower safety index are ignored
    /// @return success `True` if data for the arguments can be retrieved
    /// @return priceX96 Price of the oracle
    /// @return priceMinX96 Estimate for the lower possible price based on oracle
    /// @return priceMaxX96 Estimate for the upper possible price based on oracle
    function price(
        address token0,
        address token1,
        uint8 minSafetyIndex
    )
        external
        view
        returns (
            bool success,
            uint256 priceX96,
            uint256 priceMinX96,
            uint256 priceMaxX96
        );
}
