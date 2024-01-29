// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-test/velo/contracts/core/interfaces/ICLPool.sol";
import "./PoolAddress.sol";

/// @notice Provides validation for callbacks from CL Pools
library CallbackValidation {
    /// @notice Returns the address of a valid CL Pool
    /// @param factory The contract address of the CL factory
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param tickSpacing The tick spacing for the pool
    /// @return pool The V3 pool contract address
    function verifyCallback(
        address factory,
        address tokenA,
        address tokenB,
        int24 tickSpacing
    ) internal view returns (ICLPool pool) {
        return verifyCallback(factory, PoolAddress.getPoolKey(tokenA, tokenB, tickSpacing));
    }

    /// @notice Returns the address of a valid CL Pool
    /// @param factory The contract address of the CL factory
    /// @param poolKey The identifying key of the V3 pool
    /// @return pool The V3 pool contract address
    function verifyCallback(address factory, PoolAddress.PoolKey memory poolKey) internal view returns (ICLPool pool) {
        pool = ICLPool(PoolAddress.computeAddress(factory, poolKey));
        require(msg.sender == address(pool));
    }
}
