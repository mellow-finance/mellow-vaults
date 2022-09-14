// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/Backtest.sol";

contract ContractTest is Test {

    Backtest backtest;

    function setUp() public {
        backtest = new Backtest();
    }

    function test() public {
        backtest.execute(60, 10, 10);
    }
}
