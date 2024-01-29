// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IFeeModule.sol";

interface ICustomFeeModule is IFeeModule {
    event SetCustomFee(address indexed pool, uint24 indexed fee);

    /// @notice Returns the custom fee for a given pool if set, otherwise returns 0
    /// @dev Can use default fee by setting the fee to 0, can set zero fee by setting default fee to ZERO_FEE_INDICATOR
    /// @param pool The pool to get the custom fee for
    /// @return The custom fee for the given pool
    function customFee(address pool) external view returns (uint24);

    /// @notice Sets a custom fee for a given pool
    /// @dev Can use default fee by setting the fee to 0, can set zero fee by setting default fee to ZERO_FEE_INDICATOR
    /// @dev Must be called by the current fee manager
    /// @param pool The pool to set the custom fee for
    /// @param fee The fee to set for the given pool
    function setCustomFee(address pool, uint24 fee) external;
}
