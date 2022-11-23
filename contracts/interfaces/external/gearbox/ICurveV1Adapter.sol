// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.9;

import { IAdapter } from "./helpers/IAdapter.sol";
import { ICurvePool } from "./helpers/curve/ICurvePool.sol";

interface ICurveV1AdapterExceptions {
    error IncorrectIndexException();
}

interface ICurveV1Adapter is IAdapter, ICurvePool, ICurveV1AdapterExceptions {
    /// @dev Sends an order to exchange the entire balance of one asset to another
    /// @param i Index for the coin sent
    /// @param j Index for the coin received
    /// @param rateMinRAY Minimum exchange rate between coins i and j
    function exchange_all(
        int128 i,
        int128 j,
        uint256 rateMinRAY
    ) external;

    /// @dev Sends an order to exchange the entire balance of one underlying asset to another
    /// @param i Index for the underlying coin sent
    /// @param j Index for the underlying coin received
    /// @param rateMinRAY Minimum exchange rate between underlyings i and j
    function exchange_all_underlying(
        int128 i,
        int128 j,
        uint256 rateMinRAY
    ) external;

    /// @dev Sends an order to add liquidity with only 1 input asset
    /// @param amount Amount of asset to deposit
    /// @param i Index of the asset to deposit
    /// @param minAmount Minimal number of LP tokens to receive
    function add_liquidity_one_coin(
        uint256 amount,
        int128 i,
        uint256 minAmount
    ) external;

    /// @dev Sends an order to add liquidity with only 1 input asset, using the entire balance
    /// @param i Index of the asset to deposit
    /// @param rateMinRAY Minimal exchange rate between the deposited asset and the LP token
    function add_all_liquidity_one_coin(int128 i, uint256 rateMinRAY) external;

    /// @dev Sends an order to remove all liquidity from the pool in a single asset
    /// @param i Index of the asset to withdraw
    /// @param minRateRAY Minimal exchange rate between the LP token and the received token
    function remove_all_liquidity_one_coin(int128 i, uint256 minRateRAY)
        external;

    //
    // GETTERS
    //

    /// @dev The pool LP token
    function lp_token() external view returns (address);

    /// @dev Address of the base pool (for metapools only)
    function metapoolBase() external view returns (address);

    /// @dev Number of coins in the pool
    function nCoins() external view returns (uint256);

    /// @dev Token in the pool under index 0
    function token0() external view returns (address);

    /// @dev Token in the pool under index 1
    function token1() external view returns (address);

    /// @dev Token in the pool under index 2
    function token2() external view returns (address);

    /// @dev Token in the pool under index 3
    function token3() external view returns (address);

    /// @dev Underlying in the pool under index 0
    function underlying0() external view returns (address);

    /// @dev Underlying in the pool under index 1
    function underlying1() external view returns (address);

    /// @dev Underlying in the pool under index 2
    function underlying2() external view returns (address);

    /// @dev Underlying in the pool under index 3
    function underlying3() external view returns (address);

    /// @dev Returns the amount of lp token received when adding a single coin to the pool
    /// @param amount Amount of coin to be deposited
    /// @param i Index of a coin to be deposited
    function calc_add_one_coin(uint256 amount, int128 i)
        external
        view
        returns (uint256);
}