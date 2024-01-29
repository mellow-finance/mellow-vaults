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
        vm.startBroadcast(uint256(bytes32(vm.envBytes("OPERATOR_PK"))));
        address s = 0xb946C486d420C6597271C34ceC93e7CAEeb403bf;
        bytes memory data = hex"";
        (bool success, ) = s.call(data);
        require(success);
        vm.stopBroadcast();
    }
}
