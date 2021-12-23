// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/external/chainlink/IAggregatorV3.sol";

interface IChainlinkOracle {
    /// @notice Checks if token can be queried for price
    /// @param token token address
    /// @return `true` if token is allowed, `false` o/w
    function isAllowedToken(address token) external view returns (bool);

    /// @notice All allowed tokens
    function tokenAllowlist() external view returns (address[] memory);

    /// @notice Chainlink oracle for a ERC20 token
    /// @param token The address of the ERC20 token
    /// @return Address of the chainlink oracle
    function chainlinkOracles(address token) external view returns (address);

    /// @notice Current spot price for the tokens.
    /// @dev Throws if token is not allowed, or chainlink oracle doesn't have enough data. Required to have token1 > token0.
    /// @param token0 Token with the lower address
    /// @param token1 Token with the higher address
    /// @return priceX96 The price is `token1 / token0`, i.e. how much token1 needed to buy one unit of token0. The price is in X96 format.
    function spotPrice(address token0, address token1) external view returns (uint256 priceX96);

    /// Add a Chainlink price feed for a token
    /// @param token ERC20 token for the feed
    /// @param oracle Chainlink oracle price feed (token / USD)
    function addChainlinkOracle(address token, address oracle) external;
}
