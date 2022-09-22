// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../src/ProtocolGovernance.sol";
import "../src/VaultRegistry.sol";
import "../src/vaults/GearboxVault.sol";
import "../src/vaults/GearboxRootVault.sol";
import "../src/vaults/ERC20Vault.sol";

import "../src/vaults/GearboxVaultGovernance.sol";
import "../src/vaults/ERC20VaultGovernance.sol";
import "../src/vaults/GearboxVaultGovernance.sol";


contract CounterTest is Test {

    ProtocolGovernance governance;
    VaultRegistry registry;

    GearboxRootVault rootVault;
    ERC20Vault erc20Vault;
    GearboxVault gearboxVault;    

    function setUp() public {
        governance = new ProtocolGovernance(address(this));
        registry = new VaultRegistry("Mellow LP", "MLP", governance);

        {
            uint8[] memory args = new uint8[](2);
            args[0] = PermissionIdsLibrary.ERC20_VAULT_TOKEN;
            address usdc = 0x1F2cd0D7E5a7d8fE41f886063E9F11A05dE217Fa;
            address weth = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
            governance.stagePermissionGrants(usdc, args);
            governance.stagePermissionGrants(weth, args);

            vm.warp(block.timestamp + governance.governanceDelay());
            governance.commitPermissionGrants(usdc);
            governance.commitPermissionGrants(weth);

        }

        IVaultGovernance.InternalParams memory internalParams = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: gearboxVault
        });

        GearboxVaultGovernance governanceA = new GearboxVaultGovernance(internalParams);        

    }

    function test() public {

    }
}
