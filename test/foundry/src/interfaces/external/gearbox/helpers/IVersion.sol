// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.9;

/// @title IVersion
/// @dev Declares a version function which returns the contract's version
interface IVersion {
    /// @dev Returns contract version
    function version() external view returns (uint256);
}