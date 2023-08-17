// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IOlympusRange {
    function price(bool wall_, bool high_) external view returns (uint256);
}
