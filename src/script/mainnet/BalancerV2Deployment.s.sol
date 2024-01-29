// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/vaults/BalancerV2CSPVault.sol";
import "../../../src/vaults/BalancerV2CSPVaultGovernance.sol";

import "./Constants.sol";

contract Deploy is Script {
    using SafeERC20 for IERC20;

    function deployGovernances() public {
        BalancerV2CSPVault singleton = new BalancerV2CSPVault();
        BalancerV2CSPVaultGovernance balancerV2CSPVaultGovernance = new BalancerV2CSPVaultGovernance(
            IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(Constants.governance),
                registry: IVaultRegistry(Constants.registry),
                singleton: IVault(address(singleton))
            })
        );

        console2.log("Singleton: ", address(singleton));
        console2.log("BalancerV2CSPVaultGovernance: ", address(balancerV2CSPVaultGovernance));
    }

    // rebalance
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        deployGovernances();

        vm.stopBroadcast();
    }
}
