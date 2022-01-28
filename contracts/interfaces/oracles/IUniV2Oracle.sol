// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../external/univ2/IUniswapV2Factory.sol";

interface IUniV2Oracle {
    /// @notice Reference to UniV2 factory
    function factory() external returns (IUniswapV2Factory);

    /// @notice UniV3 prices for a token pair
    /// @dev Tokens must be sorted (token 1 > token0). Throws if univ2 pool doesn't exist.
    /// @param token0 Token 0 for price
    /// @param token1 Token 1 for price
    /// @return spotPriceX96 Current UniV3 price
    function spotPriceX96(address token0, address token1) external view returns (uint256 spotPriceX96);
}
