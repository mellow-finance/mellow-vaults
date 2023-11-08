// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IRamsesV2Pool.sol";

interface IFeeCollector {
    /// @notice Emitted when the treasury address is changed.
    /// @param oldTreasury The previous treasury address.
    /// @param newTreasury The new treasury address.
    event TreasuryChanged(address oldTreasury, address newTreasury);

    /// @notice Emitted when the treasury fees value is changed.
    /// @param oldTreasuryFees The previous value of the treasury fees.
    /// @param newTreasuryFees The new value of the treasury fees.
    event TreasuryFeesChanged(uint256 oldTreasuryFees, uint256 newTreasuryFees);

    /// @notice Emitted when protocol fees are collected from a pool and distributed to the fee distributor and treasury.
    /// @param pool The address of the pool from which the fees were collected.
    /// @param feeDistAmount0 The amount of fee tokens (token 0) distributed to the fee distributor.
    /// @param feeDistAmount1 The amount of fee tokens (token 1) distributed to the fee distributor.
    /// @param treasuryAmount0 The amount of fee tokens (token 0) allocated to the treasury.
    /// @param treasuryAmount1 The amount of fee tokens (token 1) allocated to the treasury.
    event FeesCollected(
        address pool,
        uint256 feeDistAmount0,
        uint256 feeDistAmount1,
        uint256 treasuryAmount0,
        uint256 treasuryAmount1
    );

    /// @notice Returns the treasury address.
    function treasury() external returns (address);

    /// @notice Sets the treasury address to a new value.
    /// @param newTreasury The new address to set as the treasury.
    function setTreasury(address newTreasury) external;

    /// @notice Sets the value of treasury fees to a new amount.
    /// @param _treasuryFees The new amount of treasury fees to be set.
    function setTreasuryFees(uint256 _treasuryFees) external;

    /// @notice Collects protocol fees from a specified pool and distributes them to the fee distributor and treasury.
    /// @param pool The pool from which to collect the protocol fees.
    function collectProtocolFees(IRamsesV2Pool pool) external;
}
