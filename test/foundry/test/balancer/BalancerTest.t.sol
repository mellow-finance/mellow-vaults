// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/interfaces/external/balancer/vault/IVault.sol";

contract BalancerTest is Test {
    IVault public vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address public constant GHO_WSTETH_POOL = 0x7D98f308Db99FDD04BbF4217a4be8809F38fAa64;

    function testVault() external {
        vm.startPrank(deployer);

        deal(GHO, deployer, 1e15);

        IAsset[] memory tokens = new IAsset[](2);
        tokens[0] = IAsset(GHO);
        tokens[1] = IAsset(WSTETH);
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 1000000000000000000;

        bytes
            memory userData = "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000096267833207ae00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000de0b6b3a76400000000000000000000000000000000000000000000000000000000000000000000";

        IERC20(GHO).approve(address(vault), type(uint256).max);

        vault.joinPool(
            bytes32(0x7d98f308db99fdd04bbf4217a4be8809f38faa6400020000000000000000059b),
            deployer,
            deployer,
            IVault.JoinPoolRequest({
                assets: tokens,
                maxAmountsIn: amountsIn,
                userData: userData,
                fromInternalBalance: false
            })
        );

        vm.stopPrank();
    }
}
