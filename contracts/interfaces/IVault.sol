// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IVault {
    event Push(uint256[] tokenAmounts);
    event Pull(address to, uint256[] tokenAmounts);
    event CollectEarnings(address to, address[] tokens, uint256[] tokenAmounts);
    event ReclaimTokens(address to, address[] tokens, uint256[] tokenAmounts);
}
