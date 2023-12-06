// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/utils/OmniDepositWrapper.sol";
import "../../../src/utils/PancakeOmniDepositWrapper.sol";

import "./Constants.sol";

contract Deploy is Script {
    using SafeERC20 for IERC20;

    OmniDepositWrapper public omniDepositWrapper;

    function run() external {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));

        address router = 0x678Aa4bF4E210cf2166753e054d5b7c31cc7fa86;
        address factory = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;

        // address router = 0x2626664c2603336E57B271c5C0b26F421741e481;
        // address factory = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;

        PancakeOmniDepositWrapper wrapper = new PancakeOmniDepositWrapper(router, IPancakeV3Factory(factory));

        console2.log("address:", address(wrapper));
        vm.stopBroadcast();
    }
}
