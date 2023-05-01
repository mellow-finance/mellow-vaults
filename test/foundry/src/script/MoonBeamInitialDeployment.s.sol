// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Script.sol";

import "../ProtocolGovernance.sol";
import "../VaultRegistry.sol";
import "../ERC20RootVaultHelper.sol";
import "../MockOracle.sol";

import "../vaults/ERC20Vault.sol";
import "../vaults/ERC20RootVault.sol";
import "../vaults/QuickSwapVault.sol";

import "../utils/QuickSwapHelper.sol";


import "../vaults/QuickSwapVaultGovernance.sol";
import "../vaults/ERC20VaultGovernance.sol";
import "../vaults/ERC20RootVaultGovernance.sol";

import "../validators/QuickSwapValidator.sol";
import "../validators/ERC20Validator.sol";

import "../strategies/QuickPulseStrategyV2.sol";



contract MoonBeamDeploymentA is Script {

    address public wglmr = 0xAcc15dC74880C9944775448304B263D191c6077F;
    address public usdc = 0x931715FEE2d06333043d11F658C8CE934aC61D0c;
    address public dot = 0xFfFFfFff1FcaCBd218EDc0EbA20Fc2308C778080;

    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public router = 0xe6d0ED3759709b743707DcfeCAe39BC180C981fe;
    address public factory = 0xabE1655110112D0E45EF91e94f8d757e4ddBA59C;

    function run() external {

        vm.startBroadcast();

        ProtocolGovernance governance = new ProtocolGovernance(deployer);
        VaultRegistry registry = new VaultRegistry("Registry", "MEL", governance);

        console2.log("governance: ", address(governance));
        console2.log("registry: ", address(registry));

        governance.stageUnitPrice(wglmr, 4 * 10**17);
        governance.stageUnitPrice(usdc, 10**6);
        governance.stageUnitPrice(dot, 10**10 / 5);

        governance.commitUnitPrice(wglmr);
        governance.commitUnitPrice(usdc);
        governance.commitUnitPrice(dot);

        IERC20RootVaultHelper rHelper = new ERC20RootVaultHelper();
        console2.log("root helper:", address(rHelper));

        IERC20RootVaultGovernance.DelayedProtocolParams memory rParams = IERC20RootVaultGovernance.DelayedProtocolParams({
            managementFeeChargeDelay: 86400,
            oracle: IOracle(usdc) // temporary fake oracle as we don't need any now
        });

        ERC20RootVault rv = new ERC20RootVault();

        IVaultGovernance.InternalParams memory ip = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: rv
        });

        IERC20RootVaultGovernance rootGovernance = new ERC20RootVaultGovernance(ip, rParams, rHelper);
        console2.log("root governance:", address(rootGovernance));

        ERC20Vault rrv = new ERC20Vault();

        IVaultGovernance.InternalParams memory ip2 = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: rrv
        });

        IERC20VaultGovernance erc20Governance = new ERC20VaultGovernance(ip2);
        console2.log("erc20 governance:", address(erc20Governance));

        ERC20Validator eval = new ERC20Validator(governance);
        console2.log("erc20 validator:", address(eval));

        QuickSwapValidator qval = new QuickSwapValidator(governance, router, IAlgebraFactory(factory));
        console2.log("quickswap validator:", address(qval));

        uint8[] memory g = new uint8[](2);
        g[0] = 2;
        g[1] = 3;

        governance.stageValidator(usdc, address(eval));
        governance.stageValidator(dot, address(eval));
        governance.stageValidator(wglmr, address(eval));

        governance.stagePermissionGrants(usdc, g);
        governance.stagePermissionGrants(dot, g);
        governance.stagePermissionGrants(wglmr, g);


        governance.commitValidator(usdc);
        governance.commitValidator(dot);
        governance.commitValidator(wglmr);

        governance.commitPermissionGrants(usdc);
        governance.commitPermissionGrants(dot);
        governance.commitPermissionGrants(wglmr);

        IProtocolGovernance.Params memory params = IProtocolGovernance.Params({
            maxTokensPerVault: 10,
            governanceDelay: 1,
            protocolTreasury: 0x646f851A97302Eec749105b73a45d461B810977F,
            forceAllowMask: 0,
            withdrawLimit: 200000
        });

        governance.stageParams(params);
        governance.commitParams();


    }
}