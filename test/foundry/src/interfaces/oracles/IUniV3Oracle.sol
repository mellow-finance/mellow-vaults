// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../external/univ3/IUniswapV3Factory.sol";
import "../external/univ3/IUniswapV3Pool.sol";
import "./IOracle.sol";

interface IUniV3Oracle is IOracle {
    /// @notice Reference to UniV3 factory
    function factory() external view returns (IUniswapV3Factory);

    /// @notice The number of seconds for time delta between observations for oracle safety index 2 twap
    function LOW_OBS_DELTA() external view returns (uint32);

    /// @notice The number of seconds for time delta between observations for oracle safety index 3 twap
    function MID_OBS_DELTA() external view returns (uint32);

    /// @notice The number of seconds for time delta between observations for oracle safety index 4 twap
    function HIGH_OBS_DELTA() external view returns (uint32);

    /// @notice Available UniV3 pools for tokens
    /// @param token0 First ERC20 token
    /// @param token1 Second ERC20 token
    /// @return UniV3 pool or 0 if the pool is not available for oracle
    function poolsIndex(address token0, address token1) external view returns (IUniswapV3Pool);

    /// @notice Add UniV3 pools for prices.
    /// @param pools Pools to add
    function addUniV3Pools(IUniswapV3Pool[] memory pools) external;
}
