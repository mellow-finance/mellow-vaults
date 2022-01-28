// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../external/chainlink/IAggregatorV3.sol";
import "./IExactOracle.sol";

interface IChainlinkOracle is IExactOracle {
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

    /// @notice Tells if for the token pair
    /// @param token0 Token with the lower address
    /// @param token1 Token with the higher address
    /// @return True if spot price can be queried, false otherwise
    function canTellSpotPrice(address token0, address token1) external view returns (bool);

    /// @notice Current spot price for the tokens.
    /// @dev Throws if token is not allowed, or chainlink oracle doesn't have enough data. Required to have token1 > token0.
    /// @param token0 Token with the lower address
    /// @param token1 Token with the higher address
    /// @return priceX96 The price is `token1 / token0`, i.e. how much token1 needed to buy one unit of token0. The price is in X96 format.
    function spotPriceX96(address token0, address token1) external view returns (uint256 priceX96);

    /// Add a Chainlink price feed for a token
    /// @param tokens ERC20 tokens for the feed
    /// @param oracles Chainlink oracle price feeds (token / USD)
    function addChainlinkOracles(address[] memory tokens, address[] memory oracles) external;
}
