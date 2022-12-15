// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.9;

import "../interfaces/utils/ILpCallback.sol";

contract MockLpCallback is ILpCallback {
    enum WithdrawCallbackMode {
        NO_ERROR,
        EMPTY_ERROR,
        NON_EMPTY_ERROR
    }

    WithdrawCallbackMode private _mode;

    constructor(WithdrawCallbackMode mode_) {
        _mode = mode_;
    }

    /// @notice Callback function
    function depositCallback() external {
        emit DepositCallbackCalled();
    }

    /// @notice Callback function
    function withdrawCallback() external {
        if (_mode == WithdrawCallbackMode.NO_ERROR) {
            emit WithdrawCallbackCalled();
        } else if (_mode == WithdrawCallbackMode.EMPTY_ERROR) {
            require(false);
        } else {
            require(_mode == WithdrawCallbackMode.NON_EMPTY_ERROR);
            require(false, "Error description");
        }
    }

    /// @notice Emitted when callback in depositCallback called
    event DepositCallbackCalled();

    /// @notice Emitted when callback in withdrawCallback called
    event WithdrawCallbackCalled();
}
