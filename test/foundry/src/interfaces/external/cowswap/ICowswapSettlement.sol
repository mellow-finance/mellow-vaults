// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface ICowswapSettlement {
    function domainSeparator() external view returns (bytes32);
}
