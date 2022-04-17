// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../interfaces/utils/ILpCallback.sol";
import "hardhat/console.sol";

contract MockLpCallback is ILpCallback {
    /// @notice Callback function
    function depositCallback() external {
        emit DepositCallbackCalled();
    }

    /// @notice Callback function
    function withdrawCallback() external {
        emit WithdrawCallbackCalled();    
    }

    /// @notice Emitted when callback in depositCallback called
    event DepositCallbackCalled();

    /// @notice Emitted when callback in withdrawCallback called
    event WithdrawCallbackCalled();
}
