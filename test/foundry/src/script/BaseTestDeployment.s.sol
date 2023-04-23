// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/VaultRegistry.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/MockOracle.sol";

import "../../src/utils/UniV3Helper.sol";
import "../../src/utils/LStrategyHelper.sol";
import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20RootVault.sol";

import "../../src/vaults/GearboxVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";
import "../../src/vaults/UniV3VaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";
import "../../src/strategies/LStrategy.sol";

contract BaseDeployment is Script {

    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;

    function run() external {

        vm.startBroadcast(deployer);

        ProtocolGovernance g = new ProtocolGovernance(deployer);
        VaultRegistry v = new VaultRegistry("Registry", "MEL", g);

        IProtocolGovernance.Params memory p = IProtocolGovernance.Params({
            maxTokensPerVault: 10,
            governanceDelay: 86400,
            protocolTreasury: deployer,
            forceAllowMask: 0,
            withdrawLimit: 1000000
        });

        g.stageParams(p);
        g.commitParams();

    }

}