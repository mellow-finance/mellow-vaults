// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface I3Pool {
    function coins(uint256 id) external view returns (address);

    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
}
