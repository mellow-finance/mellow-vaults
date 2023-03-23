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

        rootVault = new GearboxRootVault();
        erc20Vault = new ERC20Vault();
        gearboxVault = new GearboxVault();  

        governance = ProtocolGovernance(0xDc9C17662133fB865E7bA3198B67c53a617B2153);
        registry = VaultRegistry(0xFD23F971696576331fCF96f80a20B4D3b31ca5b2);

        IVaultGovernance.InternalParams memory internalParamsC = IVaultGovernance.InternalParams({
            protocolGovernance: governance,
            registry: registry,
            singleton: gearboxVault
        });

        IGearboxVaultGovernance.DelayedProtocolParams memory delayedParams = IGearboxVaultGovernance.DelayedProtocolParams({
            withdrawDelay: 86400 * 7,
            referralCode: 0,
            univ3Adapter: 0x3883500A0721c09DC824421B00F79ae524569E09,
            crv: 0xD533a949740bb3306d119CC777fa900bA034cd52,
            cvx: cvx,
            maxSlippageD9: 10000000,
            maxSmallPoolsSlippageD9: 20000000,
            maxCurveSlippageD9: 30000000,
            uniswapRouter: 0xE592427A0AEce92De3Edee1F18E0157C05861564
        });

        governanceA = ERC20RootVaultGovernance(0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA);
        governanceB = ERC20VaultGovernance(0x0bf7B603389795E109a13140eCb07036a1534573);
        governanceC = new GearboxVaultGovernance(internalParamsC, delayedParams);
        
        console2.log("Gearbox Vault Governance", address(governanceC));
        console2.log("Root Vault", address(rootVault));
        console2.log("ERC20 Vault", address(erc20Vault));
        console2.log("Gearbox Vault", address(gearboxVault));

        /////////////////////////////////////////////////////////////////// STOP HERE
        return;

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
        vm.stopBroadcast();
    }
}