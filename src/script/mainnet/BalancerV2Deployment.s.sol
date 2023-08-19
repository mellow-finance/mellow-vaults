// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/vaults/BalancerV2Vault.sol";
import "../../../src/vaults/BalancerV2VaultGovernance.sol";

contract BalancerV2Deployment is Script {
    using SafeERC20 for IERC20;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;

    function deployGovernances() public {
        BalancerV2Vault singleton = new BalancerV2Vault();
        BalancerV2VaultGovernance balancerV2VaultGovernance = new BalancerV2VaultGovernance(
            IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: IVaultRegistry(registry),
                singleton: IVault(address(singleton))
            })
        );

        console2.log("Singleton: ", address(singleton));
        console2.log("BalancerV2VaultGovernance: ", address(balancerV2VaultGovernance));
    }

    // rebalance
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        deployGovernances();

        vm.stopBroadcast();
    }
}
