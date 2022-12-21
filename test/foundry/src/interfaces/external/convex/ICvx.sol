// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IConvexToken {
    function totalSupply() external view returns (uint256);

    function reductionPerCliff() external view returns (uint256);

    function maxSupply() external view returns (uint256);

    function totalCliffs() external view returns (uint256);
}
