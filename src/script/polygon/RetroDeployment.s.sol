// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/vaults/ERC20RetroRootVault.sol";
import "../../../src/vaults/ERC20RetroRootVaultGovernance.sol";

import "../../../src/oracles/CASHOracle.sol";

contract RetroDeployment is Script {
    using SafeERC20 for IERC20;

    address public governance = 0x8Ff3148CE574B8e135130065B188960bA93799c6;
    address public registry = 0xd3D0e85F225348a2006270Daf624D8c46cAe4E1F;

    function deployGovernances() public {
        ERC20RetroRootVault singleton = new ERC20RetroRootVault();
        IVaultGovernance.InternalParams memory internalParams = ERC20RetroRootVaultGovernance(
            0xC12885af1d4eAfB8176905F16d23CD7A33D21f37
        ).internalParams();
        internalParams.singleton = singleton;
        ERC20RetroRootVaultGovernance retroRootVaultGovernance = new ERC20RetroRootVaultGovernance(
            internalParams,
            ERC20RetroRootVaultGovernance(0xC12885af1d4eAfB8176905F16d23CD7A33D21f37).delayedProtocolParams(),
            ERC20RetroRootVaultGovernance(0xC12885af1d4eAfB8176905F16d23CD7A33D21f37).helper()
        );

        console2.log("Singleton: ", address(singleton));
        console2.log("ERC20RetroRootVaultGovernance: ", address(retroRootVaultGovernance));
    }

    // rebalance
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        // deployGovernances();

        CASHOracle oracle = new CASHOracle();
        console2.log(uint256(oracle.latestAnswer()));

        vm.stopBroadcast();
    }
}
