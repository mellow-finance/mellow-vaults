// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import {IVault as IBalancerVault, IAsset, IERC20} from "../../src/interfaces/external/balancer/vault/IVault.sol";
import {WeightedPoolUserData} from "../../src/interfaces/external/balancer/pool-weighted/WeightedPoolUserData.sol";
import {StablePoolUserData} from "../../src/interfaces/external/balancer/pool-stable/StablePoolUserData.sol";

contract BalancerTest is Test {
    IBalancerVault public vault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    address public constant GHO_WSTETH_POOL = 0x7D98f308Db99FDD04BbF4217a4be8809F38fAa64;
    address public constant GHO_LUSD_POOL = 0x3FA8C89704e5d07565444009e5d9e624B40Be813;

    function testWeightedPool() external {
        vm.startPrank(deployer);

        bytes32 poolId = bytes32(0x7D98f308Db99FDD04BbF4217a4be8809F38fAa6400020000000000000000059b);

        IAsset[] memory tokens = new IAsset[](2);
        tokens[0] = IAsset(GHO);
        tokens[1] = IAsset(WSTETH);
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 1e18 * 1000;
        amountsIn[1] = (amountsIn[0] / 2129) * 4;

        deal(GHO, deployer, amountsIn[0]);
        deal(WSTETH, deployer, amountsIn[1]);

        bytes memory userData = abi.encode(WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, 0);

        IERC20(GHO).approve(address(vault), type(uint256).max);
        IERC20(WSTETH).approve(address(vault), type(uint256).max);

        vault.joinPool(
            poolId,
            deployer,
            deployer,
            IBalancerVault.JoinPoolRequest({
                assets: tokens,
                maxAmountsIn: amountsIn,
                userData: userData,
                fromInternalBalance: false
            })
        );

        uint256 deployerBalance = IERC20(GHO_WSTETH_POOL).balanceOf(deployer);

        userData = abi.encode(WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, deployerBalance, uint256(0));

        vault.exitPool(
            poolId,
            deployer,
            payable(deployer),
            IBalancerVault.ExitPoolRequest({
                assets: tokens,
                minAmountsOut: new uint256[](2),
                userData: userData,
                toInternalBalance: false
            })
        );

        console2.log("Deposit amount:\t", amountsIn[0], amountsIn[1]);
        console2.log("Withdraw amount:\t", IERC20(GHO).balanceOf(deployer), IERC20(WSTETH).balanceOf(deployer));

        vm.stopPrank();
    }

    function testComposableStablePool() external {
        vm.startPrank(deployer);

        bytes32 poolId = bytes32(0x3fa8c89704e5d07565444009e5d9e624b40be813000000000000000000000599);

        IAsset[] memory tokens = new IAsset[](3);
        tokens[0] = IAsset(0x3FA8C89704e5d07565444009e5d9e624B40Be813);
        tokens[1] = IAsset(GHO);
        tokens[2] = IAsset(LUSD);
        uint256[] memory amountsIn = new uint256[](3);
        amountsIn[0] = 0;
        amountsIn[1] = 274891266957476785357 * 2;
        amountsIn[2] = 722155232941573483485 * 2;

        deal(GHO, deployer, amountsIn[1]);
        deal(LUSD, deployer, amountsIn[2]);

        uint256[] memory arr = new uint256[](2);
        arr[0] = amountsIn[1];
        arr[1] = amountsIn[2];
        bytes memory userData = abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, arr, 0);

        IERC20(GHO).approve(address(vault), type(uint256).max);
        IERC20(LUSD).approve(address(vault), type(uint256).max);

        vault.joinPool(
            poolId,
            deployer,
            deployer,
            IBalancerVault.JoinPoolRequest({
                assets: tokens,
                maxAmountsIn: amountsIn,
                userData: userData,
                fromInternalBalance: false
            })
        );

        uint256 deployerBalance = IERC20(GHO_LUSD_POOL).balanceOf(deployer);
        userData = abi.encode(StablePoolUserData.ExitKind.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT, deployerBalance, uint256(0));

        vault.exitPool(
            poolId,
            deployer,
            payable(deployer),
            IBalancerVault.ExitPoolRequest({
                assets: tokens,
                minAmountsOut: new uint256[](3),
                userData: userData,
                toInternalBalance: false
            })
        );

        console2.log("Deposit amount:\t", amountsIn[1], amountsIn[2]);
        console2.log("Withdraw amount:\t", IERC20(LUSD).balanceOf(deployer), IERC20(GHO).balanceOf(deployer));

        vm.stopPrank();
    }
}
