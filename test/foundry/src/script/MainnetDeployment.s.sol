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

import "../strategies/KyberPulseStrategyV2.sol";

import "../interfaces/external/kyber/periphery/helpers/TicksFeeReader.sol";



contract MainnetDeployment is Script {

    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    IKyberVault kyberVault;

    KyberPulseStrategyV2 kyberStrategy;

    uint256 nftStart;
    address sAdmin = 0x36B16e173C5CDE5ef9f43944450a7227D71B4E31;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address public bob = 0xB0B195aEFA3650A6908f15CdaC7D92F8a5791B0B;
    address public stmatic = 0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4;
    address public governance = 0x8Ff3148CE574B8e135130065B188960bA93799c6;
    address public registry = 0xd3D0e85F225348a2006270Daf624D8c46cAe4E1F;
    address public rootGovernance = 0xC12885af1d4eAfB8176905F16d23CD7A33D21f37;
    address public erc20Governance = 0x05164eC2c3074A4E8eA20513Fbe98790FfE930A4;
    address public kyberGovernance = 0x973C5550cE03E2009BF83513f6Ea362112C75602;
    address public mellowOracle = 0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836;

    address public knc = 0x1C954E8fe737F99f68Fa1CCda3e51ebDB291948C;
    address public usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(kyberStrategy), nfts, deployer);
        rootVault = w;
        rootVaultGovernance.setStrategyParams(
            nft,
            IERC20RootVaultGovernance.StrategyParams({
                tokenLimitPerAddress: type(uint256).max,
                tokenLimit: type(uint256).max
            })
        );

        rootVaultGovernance.stageDelayedStrategyParams(
            nft,
            IERC20RootVaultGovernance.DelayedStrategyParams({
                strategyTreasury: strategyTreasury,
                strategyPerformanceTreasury: protocolTreasury,
                managementFee: 0,
                performanceFee: 0,
                privateVault: false,
                depositCallbackAddress: address(kyberStrategy),
                withdrawCallbackAddress: address(kyberStrategy)
            })
        );

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function kek() public payable returns (uint256 startNft) {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = stmatic;
        tokens[1] = bob;

        TicksFeesReader reader = new TicksFeesReader();

        KyberHelper kyberHelper = new KyberHelper(IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8), reader);

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        IOracle oracle = IOracle(0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836);

        {
            IKyberVaultGovernance kyberVaultGovernance = IKyberVaultGovernance(kyberGovernance);
/*
            bytes[] memory P = new bytes[](1);
            P[0] = abi.encodePacked(knc, uint24(1000), usdc, uint24(8), bob);

            IKyberVaultGovernance.StrategyParams memory paramsC = IKyberVaultGovernance.StrategyParams({
                farm: IKyberSwapElasticLM(0xBdEc4a045446F583dc564C0A227FFd475b329bf0),
                paths: P,
                pid: 117
            });

            vm.stopPrank();
            vm.startPrank(deployer);
*/
            kyberVaultGovernance.createVault(tokens, deployer, 40);
 //           kyberVaultGovernance.setStrategyParams(erc20VaultNft + 1, paramsC);
        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));
        kyberVault = IKyberVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        kyberStrategy = new KyberPulseStrategyV2(IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8));

        KyberPulseStrategyV2.ImmutableParams memory sParams = KyberPulseStrategyV2.ImmutableParams({
            router: 0x1111111254EEB25477B68fb85Ed929f73A960582,
            erc20Vault: erc20Vault,
            kyberVault: kyberVault,
            mellowOracle: oracle,
            tokens: tokens
        });

        uint256[] memory AA = new uint256[](2);
        AA[0] = 10**15;
        AA[1] = 10**15;

        KyberPulseStrategyV2.MutableParams memory smParams = KyberPulseStrategyV2.MutableParams({
            priceImpactD6: 0,
            defaultIntervalWidth: 4000,
            maxPositionLengthInTicks: 10000,
            maxDeviationForVaultPool: 50,
            timespanForAverageTick: 60,
            neighborhoodFactorD: 10 ** 7 * 15,
            extensionFactorD: 10 ** 9 * 2,
            swapSlippageD: 10 ** 7,
            swappingAmountsCoefficientD: 10 ** 7,
            minSwapAmounts: AA
        });

     //   kyberVault.updateFarmInfo();

     //   preparePush(address(kyberVault));

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        kyberStrategy.initialize(sParams, deployer);
        kyberStrategy.updateMutableParams(smParams);

        console2.log("strategy:", address(kyberStrategy));
        console2.log("root vault:", address(rootVault));
        console2.log("erc20 vault:", address(erc20Vault));
        console2.log("kyber vault:", address(kyberVault));
    }

    function run() external {
        vm.startBroadcast();

        kek();
    }
}