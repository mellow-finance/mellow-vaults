// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../../src/utils/DepositWrapper.sol";
import "../../../src/utils/PancakeSwapMerklHelper.sol";

import "../../../src/vaults/ERC20Vault.sol";
import "../../../src/vaults/ERC20VaultGovernance.sol";

import "../../../src/vaults/ERC20RootVault.sol";
import "../../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../../src/vaults/PancakeSwapMerklVault.sol";
import "../../../src/vaults/PancakeSwapMerklVaultGovernance.sol";

import "./Constants.sol";

contract Deploy is Script {
    using SafeERC20 for IERC20;

    function deployGovernances() public {
        PancakeSwapMerklVault singleton = new PancakeSwapMerklVault();
        PancakeSwapMerklVaultGovernance pancakeGovernance = new PancakeSwapMerklVaultGovernance(
            IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(Constants.governance),
                registry: IVaultRegistry(Constants.registry),
                singleton: IVault(address(singleton))
            }),
            IPancakeSwapMerklVaultGovernance.DelayedProtocolParams({
                positionManager: IPancakeNonfungiblePositionManager(Constants.pancakePositionManager),
                oracle: IOracle(Constants.mellowOracle)
            })
        );

        console2.log("Singleton: ", address(singleton));
        console2.log("BalancerV2CSPVaultGovernance: ", address(pancakeGovernance));
    }

    function run() external {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));
        deployGovernances();
        vm.stopBroadcast();
    }
}
