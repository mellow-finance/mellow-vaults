// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IVault as IBalancerVault, IAsset, IERC20 as IBalancerERC20} from "../../src/interfaces/external/balancer/vault/IVault.sol";
import {IBasePool} from "../../src/interfaces/external/balancer/vault/IBasePool.sol";

import "../../src/vaults/BalancerV2CSPVaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/BalancerV2CSPVault.sol";
import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20Vault.sol";

import "../../src/utils/DepositWrapper.sol";

import "../../src/strategies/BalancerVaultStrategyFix.sol";

contract BalancerCSPTest is Test {
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public admin = 0x3c1a81D6a635Db2F6d0c15FC12d43c7640cBD25f;

    address public governance = 0xCD8237f2b332e482DaEaA609D9664b739e93097d;
    address public registry = 0xc02a7B4658861108f9837007b2DF2007d6977116;

    IBalancerV2Vault public balancerVault = IBalancerV2Vault(0x0c373669783D9623471BDCa4C8Fc333d1E384a38);
    address public strategy = 0x789e03cb4adb7F0C4df3CbFC2bA2F10f4471352d;

    function test() external {
        vm.startPrank(admin);

        IProtocolGovernance(governance).stageValidator(0x2279abf4bdAb8CF29EAe4036262c62dBA6460306, 0xA9FC72eE105D43C885E48Ab18148D308A55d04c7);
        IProtocolGovernance(governance).stageValidator(0xBA12222222228d8Ba445958a75a0704d566BF2C8, 0xA9FC72eE105D43C885E48Ab18148D308A55d04c7);
        skip(24 * 60 * 60);
        IProtocolGovernance(governance).commitValidator(0x2279abf4bdAb8CF29EAe4036262c62dBA6460306);
        IProtocolGovernance(governance).commitValidator(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

        vm.stopPrank();

        vm.startPrank(deployer);
        BalancerVaultStrategyFix fix = new BalancerVaultStrategyFix();
        ITransparentUpgradeableProxy(payable(strategy)).upgradeTo(address(fix));
        vm.stopPrank();

        vm.startPrank(operator);
 
        // balancerVault.exitPool(
        //     poolId,
        //     address(this),
        //     payable(to),
        //     IBalancerVault.ExitPoolRequest({
        //         assets: tokens,
        //         minAmountsOut: minAmountsOut,
        //         userData: abi.encode(
        //             StablePoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT,
        //             actualTokenAmounts,
        //             type(uint256).max
        //         ),
        //         toInternalBalance: false
        //     })
        // );
 
        IAsset[] memory tokens = new IAsset[](3);
        tokens[0] = IAsset(0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22);
        tokens[1] = IAsset(0x4200000000000000000000000000000000000006);
        tokens[2] = IAsset(0xFb4C2E6E6e27B5b4a07a36360C89EDE29bB3c9B6);
        
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 1e9;
        tokenAmounts[1] = 1e9;

        BalancerVaultStrategyFix(strategy).liquidityWithdrawal(abi.encode(
            bytes32(0xfb4c2e6e6e27b5b4a07a36360c89ede29bb3c9b6000000000000000000000026),
            address(0x0c373669783D9623471BDCa4C8Fc333d1E384a38),
            payable(0xF891Bd91cFe262Da8de36Fc20a97Dea42EE1057c),
            IBalancerVault.ExitPoolRequest({
                assets: tokens,
                minAmountsOut: new uint256[](3),
                userData: abi.encode(
                    StablePoolUserData.ExitKind.BPT_IN_FOR_EXACT_TOKENS_OUT,
                    tokenAmounts,
                    type(uint256).max
                ),
                toInternalBalance: false
            })
        ));
        vm.stopPrank();
    }
}
