// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../external/univ3/IUniswapV3Factory.sol";
import "../external/univ3/IUniswapV3Pool.sol";
import "./IOracle.sol";

interface IUniV3Oracle is IOracle {
    /// @notice Reference to UniV3 factory
    function factory() external returns (IUniswapV3Factory);

    /// @notice Add UniV3 pools for prices.
    /// @param pools Pools to add
    function addUniV3Pools(IUniswapV3Pool[] memory pools) external;
}
