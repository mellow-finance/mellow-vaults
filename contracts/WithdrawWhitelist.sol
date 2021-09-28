// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

contract WithdrawWhitelist {
    address[] private _withdrawWhitelist;

    constructor(address[] memory withdrawWhitelist) public {
        _withdrawWhitelist = withdrawWhitelist;
    }

    function withdrawWhitelist() external view returns (address[] memory) {
        return _withdrawWhitelist;
    }

    function _doWithdraw(uint256 cell, address to, uint256 toVault) internal {

    }
}