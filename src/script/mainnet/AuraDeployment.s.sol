// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/vaults/AuraVault.sol";
import "../../../src/vaults/AuraVaultGovernance.sol";

import "../../../src/oracles/LUSDOracle.sol";

import "./Constants.sol";

contract AuraDeployment is Script {
    using SafeERC20 for IERC20;

    function deployGovernances() public {
        AuraVault singleton = new AuraVault();
        AuraVaultGovernance auraVaultGovernance = new AuraVaultGovernance(
            IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(Constants.governance),
                registry: IVaultRegistry(Constants.registry),
                singleton: IVault(address(singleton))
            })
        );

        console2.log("Singleton: ", address(singleton));
        console2.log("AuraVaultGovernance: ", address(auraVaultGovernance));
    }

    // rebalance
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        // deployGovernances();
        LUSDOracle oracle = new LUSDOracle();
        console2.log(uint256(oracle.latestAnswer()));
        vm.stopBroadcast();
    }
}
