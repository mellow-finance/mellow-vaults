// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface ILpCallback {
    /// @notice Function, that ERC20RootVault calling after deposit
    function depositCallback() external;

    /// @notice Function, that ERC20RootVault calling after withdraw
    function withdrawCallback() external;
}
