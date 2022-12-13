// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/MockOracle.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/VaultRegistry.sol";

import "../../src/vaults/GearboxVault.sol";
import "../../src/vaults/GearboxRootVault.sol";
import "../../src/vaults/ERC20Vault.sol";

import "../../src/vaults/GearboxVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/utils/GearboxHelper.sol";

import "../../src/external/ConvexBaseRewardPool.sol";

import "../../src/interfaces/external/gearbox/ICreditFacade.sol";

import "../../src/interfaces/IDegenNft.sol";

import "../helpers/MockDistributor.t.sol";

contract Zzz is Test {

    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    function setUp() public {

    }

    function test() public {
        IGearboxVault x = IGearboxVault(0x41dfc0FB65875015226073E1A4f9C24f147027BF);
        vm.startPrank(operator);

        x.adjustPosition();

    }



}
