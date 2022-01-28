// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IExactOracle {
    /// @notice Tells if for the token pair
    /// @param token Token to be queried
    /// @return `true` if exact price can be queried, `false` otherwise
    function canTellExactPrice(address token) external view returns (bool);

    /// @notice Current exact price for the token.
    /// @dev Throws if token is not allowed, or chainlink oracle doesn't have enough data.
    /// @param token Token to be queried
    /// @return priceX96 The price is `token1 / USD` in X96 format.
    function exactPriceX96(address token) external view returns (uint256 priceX96);
}
