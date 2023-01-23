// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/utils/WstethToWethAggregator.sol";


contract Rus is Test {

    function setUp() public {

    }

    function test() public {
        AggregatorV3wstEth a = new AggregatorV3wstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0, IAggregatorV3(0x86392dC19c0b719886221c78AB11eb8Cf5c52812), IAggregatorV3(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419));
        (,int256 ans,,,) = a.latestRoundData();
        console2.log(uint256(ans));
    }

    
    
}
