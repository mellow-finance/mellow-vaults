// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IDragonLair {
    function leave(uint256 _dQuickAmount) external;

    function dQUICKForQUICK(uint256 _dQuickAmount) external view returns (uint256 quickAmount_);
}
