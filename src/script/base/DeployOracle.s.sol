// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "./Constants.sol";
import "../../../src/oracles/CBETHOracle.sol";

contract Deploy is Script {
    using SafeERC20 for IERC20;

    // deploy
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        vm.stopBroadcast();
    }
}
