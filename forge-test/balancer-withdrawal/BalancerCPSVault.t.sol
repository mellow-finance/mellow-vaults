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

import "../../src/strategies/BalancerVaultStrategyV2.sol";

contract BalancerCSPTest is Test {
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public admin = 0x3c1a81D6a635Db2F6d0c15FC12d43c7640cBD25f;

    address public governance = 0xCD8237f2b332e482DaEaA609D9664b739e93097d;
    address public strategy = 0xc652000F93755A0e07Fb5b00f241189a5CC7bCd5;

    address bal = 0x4158734D47Fc9692176B5085E0F52ee0Da5d47F1;
    address weth = 0x4200000000000000000000000000000000000006;
    address balancerMinter = 0x0c5538098EBe88175078972F514C9e101D325D4F;
    address allowAllValidator = 0xA9FC72eE105D43C885E48Ab18148D308A55d04c7;

    function _test() external {
        vm.startPrank(admin);
        IProtocolGovernance(governance).stageValidator(balancerMinter, allowAllValidator);
        IProtocolGovernance(governance).stageValidator(bal, allowAllValidator);
        skip(24 * 60 * 60);
        IProtocolGovernance(governance).commitValidator(balancerMinter);
        IProtocolGovernance(governance).commitValidator(bal);
        vm.stopPrank();

        vm.startPrank(deployer);
        BalancerVaultStrategyV2 fix = new BalancerVaultStrategyV2();
        ITransparentUpgradeableProxy(payable(strategy)).upgradeTo(address(fix));
        vm.stopPrank();

        vm.startPrank(operator);
        BalancerVaultStrategyV2(strategy).setRewardTokens(new address[](0));
        IERC20Vault erc20Vault = BalancerVaultStrategyV2(strategy).erc20Vault();
        console2.log("weth Balance before: ", IERC20(weth).balanceOf(address(erc20Vault)));
        BalancerVaultStrategyV2(strategy).compound(new bytes[](0), 0, type(uint256).max);
        console2.log("weth Balance after: ", IERC20(weth).balanceOf(address(erc20Vault)));
        vm.stopPrank();
    }
}
