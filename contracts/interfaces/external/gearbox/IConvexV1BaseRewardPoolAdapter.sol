// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.9;

import { IAdapter } from "./helpers/IAdapter.sol";
import { IBaseRewardPool } from "./helpers/convex/IBaseRewardPool.sol";

interface IConvexV1BaseRewardPoolAdapterErrors {
    /// @dev Thrown when the adapter attempts to use a token not
    ///      allowed in its corresponding Credit Manager
    error TokenIsNotAddedToCreditManagerException(address token);
}

interface IConvexV1BaseRewardPoolAdapter is
    IAdapter,
    IBaseRewardPool,
    IConvexV1BaseRewardPoolAdapterErrors
{
    /// @dev Returns the address of a Curve pool LP token
    ///      staked in the adapter's targer Convex pool
    function curveLPtoken() external view returns (address);

    /// @dev Returns the address of a phantom token tracking
    ///      a Credit Account's staked balance in a Convex
    ///      pool
    function stakedPhantomToken() external view returns (address);

    /// @dev Returns the address of the first extra reward token
    /// @notice address(0) if the Convex pool has no extra reward tokens
    function extraReward1() external view returns (address);

    /// @dev Returns the address of the second extra reward token
    /// @notice address(0) if the Convex pool has less than 2 extra reward tokens
    function extraReward2() external view returns (address);

    /// @dev Returns the address of CVX
    function cvx() external view returns (address);
}