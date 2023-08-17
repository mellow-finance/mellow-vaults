// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import {IVault as IBalancerVault, IAsset, IERC20 as IBalancerERC20} from "../../../src/interfaces/external/balancer/vault/IVault.sol";
import {IBasePool} from "../../../src/interfaces/external/balancer/vault/IBasePool.sol";

import "../../../src/vaults/BalancerV2VaultGovernance.sol";
import "../../../src/vaults/ERC20RootVaultGovernance.sol";
import "../../../src/vaults/ERC20VaultGovernance.sol";

import "../../../src/vaults/BalancerV2Vault.sol";
import "../../../src/vaults/ERC20RootVault.sol";
import "../../../src/vaults/ERC20Vault.sol";

import "../../../src/utils/DepositWrapper.sol";

contract BalancerTest is Test {
    IBalancerVault public vault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    address public constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    address public constant GHO_WSTETH_POOL = 0x7D98f308Db99FDD04BbF4217a4be8809F38fAa64;
    address public constant GHO_LUSD_POOL = 0x3FA8C89704e5d07565444009e5d9e624B40Be813;
    address public constant GHO_BOOSTED_STABLE_POOL = 0xc2B021133D1b0cF07dba696fd5DD89338428225B;

    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;

    function testWeightedPool() external {
        vm.startPrank(deployer);

        // IBalancerMinter minter = IBalancerMinter(0x239e55F427D44C3cc793f49bFB507ebe76638a2b);
        IStakingLiquidityGauge gauge = IStakingLiquidityGauge(0x6EE63656BbF5BE3fdF9Be4982BF9466F6a921b83);
        bytes32 poolId = IBasePool(GHO_WSTETH_POOL).getPoolId();
        (IBalancerERC20[] memory poolTokens, uint256[] memory poolTokenAmounts, ) = vault.getPoolTokens(poolId);
        IAsset[] memory tokens = new IAsset[](poolTokens.length);
        uint256[] memory amountsIn = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            tokens[i] = IAsset(address(poolTokens[i]));
            console2.log("Token ", i, address(tokens[i]));
            amountsIn[i] = poolTokenAmounts[i] / 100;
        }

        deal(GHO, deployer, amountsIn[0]);
        deal(WSTETH, deployer, amountsIn[1]);

        bytes memory userData = abi.encode(WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, 0);

        IERC20(GHO).approve(address(vault), type(uint256).max);
        IERC20(WSTETH).approve(address(vault), type(uint256).max);

        console2.log(IERC20(GHO_WSTETH_POOL).balanceOf(deployer), IERC20(address(gauge)).balanceOf(deployer));
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

        IERC20(GHO_WSTETH_POOL).approve(address(gauge), type(uint256).max);

        console2.log(IERC20(GHO_WSTETH_POOL).balanceOf(deployer), IERC20(address(gauge)).balanceOf(deployer));
        gauge.deposit(deployerBalance, deployer);

        console2.log(IERC20(GHO_WSTETH_POOL).balanceOf(deployer), IERC20(address(gauge)).balanceOf(deployer));

        skip(60 * 60);

        // uint256 balAmount = minter.mint(address(gauge));
        // console2.log(balAmount);

        console2.log(IERC20(GHO_WSTETH_POOL).balanceOf(deployer), IERC20(address(gauge)).balanceOf(deployer));

        gauge.withdraw(deployerBalance);

        console2.log(IERC20(GHO_WSTETH_POOL).balanceOf(deployer), IERC20(address(gauge)).balanceOf(deployer));

        userData = abi.encode(WeightedPoolUserData.ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, deployerBalance, uint256(0));

        vault.exitPool(
            poolId,
            deployer,
            payable(deployer),
            IBalancerVault.ExitPoolRequest({
                assets: tokens,
                minAmountsOut: new uint256[](tokens.length),
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

        bytes32 poolId = IBasePool(GHO_LUSD_POOL).getPoolId();

        (IBalancerERC20[] memory poolTokens, uint256[] memory poolTokenAmounts, ) = vault.getPoolTokens(poolId);
        IAsset[] memory tokens = new IAsset[](poolTokens.length);
        uint256[] memory amountsIn = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < poolTokens.length; i++) {
            tokens[i] = IAsset(address(poolTokens[i]));
            console2.log("Token ", i, address(tokens[i]));
            amountsIn[i] = poolTokenAmounts[i] / 100;
        }
        amountsIn[0] = 0;

        deal(GHO, deployer, amountsIn[1]);
        deal(LUSD, deployer, amountsIn[2]);

        uint256[] memory arr = new uint256[](2);
        uint256 minLpAmount = 0;
        arr[0] = amountsIn[1];
        arr[1] = amountsIn[2];
        bytes memory userData = abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, arr, minLpAmount);

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
                minAmountsOut: new uint256[](tokens.length),
                userData: userData,
                toInternalBalance: false
            })
        );

        console2.log("Deposit amount:\t", amountsIn[0], amountsIn[1], amountsIn[2]);
        console2.log(
            "Withdraw amount:\t",
            IERC20(address(tokens[0])).balanceOf(deployer),
            IERC20(address(tokens[1])).balanceOf(deployer),
            IERC20(address(tokens[2])).balanceOf(deployer)
        );

        vm.stopPrank();
    }

    function testOneTokenComposableStablePool() external {
        vm.startPrank(deployer);

        bytes32 poolId = IBasePool(GHO_BOOSTED_STABLE_POOL).getPoolId();

        (IBalancerERC20[] memory poolTokens, , ) = vault.getPoolTokens(poolId);
        IAsset[] memory tokens = new IAsset[](poolTokens.length);
        uint256[] memory amountsIn = new uint256[](poolTokens.length);
        uint256 ghoIndex = 0;
        for (uint256 i = 0; i < poolTokens.length; i++) {
            tokens[i] = IAsset(address(poolTokens[i]));
            console2.log("Token ", i, address(tokens[i]));
            if (address(poolTokens[i]) == GHO) {
                ghoIndex = i;
            }
        }

        amountsIn[ghoIndex] = 1e18 * 1000;
        deal(GHO, deployer, amountsIn[ghoIndex]);

        uint256[] memory arr = new uint256[](2);
        uint256 minLpAmount = 0;
        arr[0] = amountsIn[ghoIndex];

        bytes memory userData = abi.encode(StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, arr, minLpAmount);

        IERC20(GHO).approve(address(vault), type(uint256).max);

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

        uint256 deployerBalance = IERC20(GHO_BOOSTED_STABLE_POOL).balanceOf(deployer);
        userData = abi.encode(StablePoolUserData.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, deployerBalance, uint256(0));

        vault.exitPool(
            poolId,
            deployer,
            payable(deployer),
            IBalancerVault.ExitPoolRequest({
                assets: tokens,
                minAmountsOut: new uint256[](tokens.length),
                userData: userData,
                toInternalBalance: false
            })
        );

        console2.log("Deposit amount:\t", amountsIn[0], amountsIn[1], amountsIn[2]);
        console2.log(
            "Withdraw amount:\t",
            IERC20(address(tokens[0])).balanceOf(deployer),
            IERC20(address(tokens[1])).balanceOf(deployer),
            IERC20(address(tokens[2])).balanceOf(deployer)
        );

        vm.stopPrank();
    }
}
