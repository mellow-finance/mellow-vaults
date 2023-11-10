// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../../src/vaults/RamsesV2Vault.sol";
import "../../../src/vaults/RamsesV2VaultGovernance.sol";

import "./Constants.sol";

contract Deploy is Script {
    using SafeERC20 for IERC20;

    function deployGovernances() public {
        RamsesV2Vault singleton = new RamsesV2Vault();
        RamsesV2VaultGovernance governance = new RamsesV2VaultGovernance(
            IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(Constants.governance),
                registry: IVaultRegistry(Constants.registry),
                singleton: IVault(address(singleton))
            }),
            IRamsesV2VaultGovernance.DelayedProtocolParams({
                positionManager: IRamsesV2NonfungiblePositionManager(Constants.ramsesPositionManager),
                oracle: IOracle(Constants.mellowOracle)
            })
        );

        console2.log("Singleton: ", address(singleton));
        console2.log("RamsesV2VaultGovernance: ", address(governance));
    }

    // rebalance
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        deployGovernances();

        vm.stopBroadcast();
    }
}
