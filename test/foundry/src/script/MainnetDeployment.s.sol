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

import "../vaults/GearboxVaultGovernance.sol";
import "../vaults/ERC20VaultGovernance.sol";
import "../vaults/ERC20RootVaultGovernance.sol";



contract MainnetDeployment is Script {

    ProtocolGovernance governance;
    VaultRegistry registry;

    GearboxRootVault rootVault;
    ERC20Vault erc20Vault;
    GearboxVault gearboxVault;

    ERC20RootVaultGovernance governanceA; 
    ERC20VaultGovernance governanceB;
    GearboxVaultGovernance governanceC;

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

        governance = ProtocolGovernance(0xDc9C17662133fB865E7bA3198B67c53a617B2153);
        registry = VaultRegistry(0xFD23F971696576331fCF96f80a20B4D3b31ca5b2);

        rootVault = new GearboxRootVault();
        gearboxVault = new GearboxVault();

        console2.log("Mock Gearbox Root Vault: ", address(rootVault));
        console2.log("Mock Gearbox Vault: ", address(gearboxVault));
        
        IVaultGovernance.InternalParams memory internalParamsA = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: rootVault
        }); // INTERNAL PARAMS FOR NEW GEARBOXROOTVAULTGOVERNANCE WHICH IS THE SAME AS ERC20ROOTVAULTGOVERNANCE

        IVaultGovernance.InternalParams memory internalParamsB = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: gearboxVault
        }); // INTERNAL PARAMS FOR NEW GEARBOXVAULTGOVERNANCE WHICH IS THE SAME AS ERC20ROOTVAULTGOVERNANCE

        IGearboxVaultGovernance.DelayedProtocolParams memory delayedParamsB = IGearboxVaultGovernance.DelayedProtocolParams({
            crv3Pool: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7,
            crv: 0xD533a949740bb3306d119CC777fa900bA034cd52,
            cvx: cvx,
            maxSlippageD9: 10000000,
            maxSmallPoolsSlippageD9: 40000000,
            maxCurveSlippageD9: 30000000,
            uniswapRouter: 0xE592427A0AEce92De3Edee1F18E0157C05861564
        });

        ERC20RootVaultHelper helper = ERC20RootVaultHelper(0xACEE4A703f27eA1EbCd550511aAE58ad012624CC);

        IERC20RootVaultGovernance.DelayedProtocolParams memory delayedParamsA = IERC20RootVaultGovernance.DelayedProtocolParams({
            managementFeeChargeDelay: 86400,
            oracle: IOracle(0x9d992650B30C6FB7a83E7e7a430b4e015433b838)
        });
        
        governanceA = new ERC20RootVaultGovernance(internalParamsA, delayedParamsA, helper); // => GEARBOX ROOT VAULT GOVERNANCE
        governanceB = ERC20VaultGovernance(0x0bf7B603389795E109a13140eCb07036a1534573);
        governanceC = new GearboxVaultGovernance(internalParamsB, delayedParamsB);

        console2.log("Gearbox Governance: ", address(governanceC));
        console2.log("Gearbox Root Governance: ", address(governanceA));

        vm.stopBroadcast();
        return;
/*    
    /////////////////////////////////////////////// UP TO SIGN IN 24H
        uint8[] memory args = new uint8[](1);
        args[0] = PermissionIdsLibrary.REGISTER_VAULT;

        governance.stagePermissionGrants(address(governanceA), args);
        governance.commitPermissionGrants(address(governanceA));
    ///////////////////////////////////////////////

    */

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
            univ3Adapter: 0x3883500A0721c09DC824421B00F79ae524569E09, // find
            facade: 0x61fbb350e39cc7bF22C01A469cf03085774184aa,
            withdrawDelay: 86400 * 30,
            initialMarginalValueD9: 5000000000,
            referralCode: 0
        });

        IGearboxVaultGovernance.StrategyParams memory strategyParamsB = IGearboxVaultGovernance.StrategyParams({
            largePoolFeeUsed: 500
        });
/*
        ////////////////////// TO BE SIGNED INSTANTLY
        governanceC.stageDelayedProtocolPerVaultParams(nftStart + 1, delayedVaultParams);
        governanceC.commitDelayedProtocolPerVaultParams(nftStart + 1);
        //////////////////////
*/

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

        rootVault = GearboxRootVault(registry.vaultForNft(nftStart + 2));
        erc20Vault = ERC20Vault(registry.vaultForNft(nftStart));
        gearboxVault = GearboxVault(registry.vaultForNft(nftStart + 1));

        console2.log("Root Vault: ", address(rootVault));
        console2.log("ERC20 Vault: ", address(erc20Vault));
        console2.log("Gearbox Vault: ", address(gearboxVault));
        
        governanceA.stageDelayedStrategyParams(nftStart + 2, delayedStrategyParams);
        governanceA.commitDelayedStrategyParams(nftStart + 2);
        governanceA.setStrategyParams(nftStart + 2, strategyParams);

        registry.approve(operator, nftStart + 2);
        registry.transferFrom(deployer, sAdmin, nftStart + 2);

        // DO FROM OPERATOR: governanceC.setStrategyParams(nftStart + 1, strategyParamsB);

        vm.stopBroadcast();
    }
}