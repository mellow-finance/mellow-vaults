// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Script.sol";

import "../ProtocolGovernance.sol";
import "../VaultRegistry.sol";
import "../ERC20RootVaultHelper.sol";
import "../MockOracle.sol";

import "../vaults/GearboxVault.sol";
import "../vaults/GearboxRootVault.sol";
import "../vaults/ERC20Vault.sol";
import "../vaults/KyberVault.sol";

import "../utils/KyberHelper.sol";

import "../vaults/KyberVaultGovernance.sol";
import "../vaults/GearboxVaultGovernance.sol";
import "../vaults/ERC20VaultGovernance.sol";
import "../vaults/ERC20RootVaultGovernance.sol";

import "../interfaces/external/kyber/periphery/helpers/TicksFeeReader.sol";



contract MainnetDeployment is Script {

    ProtocolGovernance governance;
    VaultRegistry registry;

    KyberVault kyberVault;

    ERC20RootVaultGovernance governanceA; 
    ERC20VaultGovernance governanceB;
    KyberVaultGovernance governanceC;

    uint256 nftStart;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    function run() external {
        vm.startBroadcast();

        TicksFeesReader reader = new TicksFeesReader();
        KyberHelper kyberHelper = new KyberHelper(IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8), reader);

        console.log("reader:", address(reader));
        console.log("helper:", address(kyberHelper));

        kyberVault = new KyberVault(IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8), IRouter(0xC1e7dFE73E1598E3910EF4C7845B68A9Ab6F4c83), kyberHelper, IOracle(0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836));

        console.log("mock kyber vault:", address(kyberVault));

        governance = ProtocolGovernance(0x8Ff3148CE574B8e135130065B188960bA93799c6);
        registry = VaultRegistry(0xd3D0e85F225348a2006270Daf624D8c46cAe4E1F);

        IVaultGovernance.InternalParams memory internalParamsC = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: kyberVault
        });

        governanceC = new KyberVaultGovernance(internalParamsC);
        
        console2.log("Kyber Vault Governance", address(governanceC));

        /////////////////////////////////////////////////////////////////// STOP HERE
        return;
/*
        {
            uint8[] memory args = new uint8[](1);
            args[0] = PermissionIdsLibrary.REGISTER_VAULT;
            governance.stagePermissionGrants(address(governanceC), args);
            governance.commitPermissionGrants(address(governanceC));
        }

        IERC20RootVaultGovernance.StrategyParams memory strategyParams = IERC20RootVaultGovernance.StrategyParams({
            tokenLimitPerAddress: type(uint256).max,
            tokenLimit: type(uint256).max
        });

        IERC20RootVaultGovernance.DelayedStrategyParams memory delayedStrategyParams = IERC20RootVaultGovernance.DelayedStrategyParams({
            strategyTreasury: strategyTreasury,
            strategyPerformanceTreasury: protocolTreasury,
            privateVault: true,
            managementFee: 0,
            performanceFee: 0,
            depositCallbackAddress: address(0),
            withdrawCallbackAddress: address(0)
        });

        nftStart = registry.vaultsCount() + 1;

        IGearboxVaultGovernance.DelayedProtocolPerVaultParams memory delayedVaultParams = IGearboxVaultGovernance.DelayedProtocolPerVaultParams({
            primaryToken: usdc,
            curveAdapter: 0x6f3A4EFe549c2Fa397ed40FD4DE9FEB922C0FE31,
            convexAdapter: 0xb26586F4a9F157117651Da1A6DFa5b310790dd8A,
            facade: 0xCd290664b0AE34D8a7249bc02d7bdbeDdf969820,
            initialMarginalValueD9: 5000000000
        });

        IGearboxVaultGovernance.StrategyParams memory strategyParamsB = IGearboxVaultGovernance.StrategyParams({
            largePoolFeeUsed: 500
        });

        governanceA.stageDelayedStrategyParams(nftStart + 2, delayedStrategyParams);
        governanceC.stageDelayedProtocolPerVaultParams(nftStart + 1, delayedVaultParams);
        governanceC.setStrategyParams(nftStart + 1, strategyParamsB);
        governanceC.commitDelayedProtocolPerVaultParams(nftStart + 1);
        governanceA.commitDelayedStrategyParams(nftStart + 2);

        address[] memory tokens = new address[](1);
        tokens[0] = usdc; 

        GearboxHelper helper2 = new GearboxHelper();

        governanceB.createVault(tokens, deployer);
        governanceC.createVault(tokens, deployer, address(helper2));

        uint256[] memory nfts = new uint256[](2);

        nfts[0] = nftStart;
        nfts[1] = nftStart + 1;

        registry.approve(address(governanceA), nftStart);
        registry.approve(address(governanceA), nftStart + 1);

        governanceA.createVault(tokens, operator, nfts, deployer);

        registry.approve(operator, nftStart + 2);
        registry.transferFrom(deployer, sAdmin, nftStart + 2);

        governanceA.setStrategyParams(nftStart + 2, strategyParams);
        */
        vm.stopBroadcast();
    }
}