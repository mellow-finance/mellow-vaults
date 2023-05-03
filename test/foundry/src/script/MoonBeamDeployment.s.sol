// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/utils/QuickSwapHelper.sol";
import "../../src/utils/DepositWrapper.sol";
import "../../src/MockOracle.sol";

import "../../src/vaults/QuickSwapVaultGovernance.sol";
import "../../src/strategies/QuickPulseStrategyV2.sol";

import "../../src/interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../../src/interfaces/vaults/IERC20VaultGovernance.sol";
import "../../src/interfaces/vaults/IQuickSwapVaultGovernance.sol";

import "../../src/interfaces/vaults/IERC20RootVault.sol";
import "../../src/interfaces/vaults/IERC20Vault.sol";
import "../../src/interfaces/vaults/IQuickSwapVault.sol";

import "../../src/vaults/QuickSwapVault.sol";

contract MoonBeamDeploymentB is Script {

    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    IQuickSwapVault quickswapVault;

    QuickPulseStrategyV2 strategy;

    uint256 nftStart;
    address sAdmin = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address protocolTreasury = 0xDF6780faC92ec8D5f366584c29599eA1c97C77F5;
    address strategyTreasury = 0xb0426fDFEfF47B23E5c2794D406A3cC8E77Ec001;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;

    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address admin = 0x7ee9247b6199877F86703644c97784495549aC5E;

    address public wglmr = 0xAcc15dC74880C9944775448304B263D191c6077F;
    address public usdc = 0x931715FEE2d06333043d11F658C8CE934aC61D0c;

    address public governance = 0xD1770b8Ce5943F40186747718FB6eD0b4dcf86a4;
    address public registry = 0x6A4c92818C956AFC22eb33ce50b65090e9187FFD;

    address public rootGovernance = 0xa81A613f28C1978Ac95C5cd9Ec8f80AD613d0F15;
    address public erc20Governance = 0x646241a254A315c136826a6BF0f1709616621ecF;

    address public manager = 0x1FF2ADAa387dD27c22b31086E658108588eDa03a;
    address public router = 0xe6d0ED3759709b743707DcfeCAe39BC180C981fe;
    address public factory = 0xabE1655110112D0E45EF91e94f8d757e4ddBA59C;
    address public farm = 0x0D4F8A55a5B2583189468ca3b0A32d972f90e6e5;

    address public pool = 0xaB8C35164a8e3EF302d18DA953923eA31f0Fe393;

    IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    function firstDeposit() public {

        uint256[] memory amounts = new uint256[](2);

        amounts[0] = 10**4;
        amounts[1] = 10**10;

        IERC20(wglmr).approve(address(rootVault), type(uint256).max);
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function deposit(uint256 amount) public {

        if (rootVault.totalSupply() == 0) {
            firstDeposit();
        }

        uint256[] memory amounts = new uint256[](2);

        amounts[0] = amount * 10**6;
        amounts[1] = amount * 10**18;

        IERC20(wglmr).approve(address(rootVault), type(uint256).max);
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(strategy), nfts, deployer);
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
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    address[] tokens;

    function kek() public payable returns (uint256 startNft) {

/*
        {
            uint8[] memory grant = new uint8[](1);
            grant[0] = 4;

            IProtocolGovernance gv = IProtocolGovernance(governance);

           // gv.stagePermissionGrants(address(router), grant);
           // gv.stagePermissionGrants(address(pool), grant);
            gv.commitPermissionGrants(address(router));
            gv.commitPermissionGrants(address(pool));

        }

        return 0;
*/

        //address W = 0x04a02e3e65Fed5d93e3B7Bf7eB3E5beEa5dd212a;

        //IProtocolGovernance(governance).stageValidator(address(router), W);
   //     IProtocolGovernance(governance).commitValidator(address(router));
    //    return 0;

        

        tokens = new address[](2);

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
       // uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        uint256 erc20VaultNft = vaultRegistry.vaultsCount();

        tokens[0] = usdc;
        tokens[1] = wglmr;

       // IQuickSwapHelper helper = new QuickSwapHelper(IAlgebraNonfungiblePositionManager(manager), address(0), address(0));
/*
        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }
*/
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        {

         //   QuickSwapVault k = new QuickSwapVault(IAlgebraNonfungiblePositionManager(manager), helper, IAlgebraSwapRouter(router), IFarmingCenter(farm), address(0), address(0));
/*
            IVaultGovernance.InternalParams memory paramsA = IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: vaultRegistry,
                singleton: k
            });
    */

            IQuickSwapVaultGovernance quickSwapVaultGovernance = IQuickSwapVaultGovernance(0x85344A85CC52512c20318Ab349F3E5c25E3CA592);

          //  console2.log("quick governance:", address(quickSwapVaultGovernance));

            {

                // uint8[] memory grant2 = new uint8[](1);

               // IProtocolGovernance gv = IProtocolGovernance(governance);

              //  gv.stagePermissionGrants(address(quickSwapVaultGovernance), grant2);
             //   gv.commitPermissionGrants(address(quickSwapVaultGovernance));

              //  return 0;

            }

            quickSwapVaultGovernance.createVault(tokens, deployer, address(erc20Vault));

            IIncentiveKey.IncentiveKey memory key = IIncentiveKey.IncentiveKey({
                rewardToken: IERC20Minimal(0x0E358838ce72d5e61E0018a2ffaC4bEC5F4c88d2),
                bonusRewardToken: IERC20Minimal(0xAcc15dC74880C9944775448304B263D191c6077F),
                pool: IAlgebraPool(0xaB8C35164a8e3EF302d18DA953923eA31f0Fe393),
                startTime: 1679238000,
                endTime: 2024838000
            });

            IQuickSwapVaultGovernance.StrategyParams memory qsp = IQuickSwapVaultGovernance.StrategyParams({
                key: key,
                bonusTokenToUnderlying: wglmr,
                rewardTokenToUnderlying: wglmr,
                swapSlippageD: 10**7,
                rewardPoolTimespan: 300
            });

            quickSwapVaultGovernance.setStrategyParams(erc20VaultNft + 1, qsp);
        }

        quickswapVault = IQuickSwapVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        strategy = new QuickPulseStrategyV2(IAlgebraNonfungiblePositionManager(manager));


        QuickPulseStrategyV2.ImmutableParams memory sParams = QuickPulseStrategyV2.ImmutableParams({
            erc20Vault: erc20Vault,
            quickSwapVault: quickswapVault,
            router: router,
            tokens: tokens
        });

        uint256[] memory AA = new uint256[](2);
        
        AA[0] = 10**3;
        AA[1] = 10**12;

        QuickPulseStrategyV2.MutableParams memory smParams = QuickPulseStrategyV2.MutableParams({
            priceImpactD6: 5000,
            defaultIntervalWidth: 4200,
            maxPositionLengthInTicks: 15000,
            maxDeviationForVaultPool: 50,
            timespanForAverageTick: 300,
            neighborhoodFactorD: 15 * 10**7,
            extensionFactorD: 175 * 10**7,
            swapSlippageD: 2 * 10 ** 7,
            swappingAmountsCoefficientD: 10 ** 7,
            minSwapAmounts: AA
        });

        QuickPulseStrategyV2.DesiredAmounts memory smmParams = QuickPulseStrategyV2.DesiredAmounts({
            amount0Desired: 10 ** 9,
            amount1Desired: 10 ** 9
        });

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        strategy.initialize(sParams, deployer);
        strategy.updateMutableParams(smParams);
        strategy.updateDesiredAmounts(smmParams);

        console2.log("strategy:", address(strategy));
        console2.log("erc20 vault:", address(erc20Vault));
        console2.log("root vault:", address(rootVault));
        console2.log("quick vault:", address(quickswapVault));

        IERC20(wglmr).transfer(address(strategy), 10**9);
        IERC20(usdc).transfer(address(strategy), 10**3);
    }

    function smallDepositRebalance() public {
        firstDeposit();
        deposit(1);

        bytes4 selector = IAlgebraSwapRouter.exactInputSingle.selector;

        uint256 tokenIn = 0;
        uint256 amount = 511193;

        bytes memory swapdata = abi.encodePacked(selector, abi.encode(tokens[tokenIn], tokens[1 - tokenIn], address(erc20Vault), type(uint256).max, amount, uint256(0), uint160(0)));

        strategy.rebalance(block.timestamp + 10000, swapdata, 0);
    }

    function run() external {

        vm.startBroadcast();

        DepositWrapper d = new DepositWrapper(deployer);
        console.log("moonbeam wrapper:", address(d));

        return;

        kek();
        smallDepositRebalance();
    }
}