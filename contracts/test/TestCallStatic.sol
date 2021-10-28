// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract TestCallStatic {
    uint256 private _a;

    function incA() external returns (uint256) {
        _a += 1;
        return _a;
    }

    function a() external view returns (uint256) {
        return _a;
    }
}
