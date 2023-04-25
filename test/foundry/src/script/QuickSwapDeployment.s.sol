// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/Script.sol";

import "../ProtocolGovernance.sol";
import "../VaultRegistry.sol";
import "../ERC20RootVaultHelper.sol";
import "../MockOracle.sol";

import "../vaults/GearboxVault.sol";
import "../vaults/GearboxRootVault.sol";
import "../vaults/ERC20Vault.sol";
import "../vaults/QuickSwapVault.sol";

import "../utils/QuickSwapHelper.sol";

import "../vaults/QuickSwapVaultGovernance.sol";
import "../vaults/ERC20VaultGovernance.sol";
import "../vaults/ERC20RootVaultGovernance.sol";

import "../strategies/QuickPulseStrategyV2.sol";



contract QuickSwapDeployment is Script {

    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    IQuickSwapVault quickVault;

    QuickPulseStrategyV2 strategy;

    uint256 nftStart;
    address sAdmin = 0x36B16e173C5CDE5ef9f43944450a7227D71B4E31;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;
    address wrapper = 0xa5Ece1f667DF4faa82cF29959517a15f84fD7862;

    address public weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public bob = 0xB0B195aEFA3650A6908f15CdaC7D92F8a5791B0B;

    address public governance = 0x8Ff3148CE574B8e135130065B188960bA93799c6;
    address public registry = 0xd3D0e85F225348a2006270Daf624D8c46cAe4E1F;

    address public rootGovernance = 0xC12885af1d4eAfB8176905F16d23CD7A33D21f37;
    address public erc20Governance = 0x05164eC2c3074A4E8eA20513Fbe98790FfE930A4;
    address public quickGovernance = 0xaC2A04502929436062e2D0e8b9fD16b2C85fBD88;

    address public mellowOracle = 0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836;

    IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

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
                privateVault: true,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function kek() public payable returns (uint256 startNft) {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = bob;

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        IOracle oracle = IOracle(0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836);

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

   //     QuickSwapHelper helper = new QuickSwapHelper(IAlgebraNonfungiblePositionManager(0x8eF88E4c7CfbbaC1C163f7eddd4B578792201de6), 0xB5C064F955D8e7F38fE0460C556a72987494eE17, 0x958d208Cdf087843e9AD98d23823d32E17d723A1);

        {
/*
            IVault w = new QuickSwapVault(IAlgebraNonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88), IQuickSwapHelper(helper), IAlgebraSwapRouter(0xf5b509bB0909a69B1c207E495f687a596C168E12), IFarmingCenter(0x7F281A8cdF66eF5e9db8434Ec6D97acc1bc01E78), 0x958d208Cdf087843e9AD98d23823d32E17d723A1, 0xB5C064F955D8e7F38fE0460C556a72987494eE17);

            IVaultGovernance.InternalParams memory p = IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: IVaultRegistry(registry),
                singleton: w
            });
*/
            IQuickSwapVaultGovernance quickGovernanceC = QuickSwapVaultGovernance(0xaC2A04502929436062e2D0e8b9fD16b2C85fBD88);
            quickGovernanceC.createVault(tokens, deployer, address(erc20Vault));

            IQuickSwapVaultGovernance.StrategyParams memory sp = IQuickSwapVaultGovernance.StrategyParams({
                key: IIncentiveKey.IncentiveKey({
                    rewardToken: IERC20Minimal(0x958d208Cdf087843e9AD98d23823d32E17d723A1),
                    bonusRewardToken: IERC20Minimal(0xB0B195aEFA3650A6908f15CdaC7D92F8a5791B0B),
                    pool: IAlgebraPool(0x1f97c0260C6a18B26a9C2681F0fAa93aC2182dbC),
                    startTime: 1669833619,
                    endTime: 4104559500
                }),
                bonusTokenToUnderlying: 0xB0B195aEFA3650A6908f15CdaC7D92F8a5791B0B,
                rewardTokenToUnderlying: 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619,
                swapSlippageD: 10**7,
                rewardPoolTimespan: 60
            });

            quickGovernanceC.setStrategyParams(erc20VaultNft + 1, sp);
        }

        quickVault = IQuickSwapVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        QuickPulseStrategyV2 protoS = new QuickPulseStrategyV2(IAlgebraNonfungiblePositionManager(0x8eF88E4c7CfbbaC1C163f7eddd4B578792201de6));
        TransparentUpgradeableProxy kek = new TransparentUpgradeableProxy(address(protoS), sAdmin, "");
        strategy = QuickPulseStrategyV2(address(kek));

        QuickPulseStrategyV2.ImmutableParams memory sParams = QuickPulseStrategyV2.ImmutableParams({
            erc20Vault: erc20Vault,
            quickSwapVault: quickVault,
            router: 0x1111111254EEB25477B68fb85Ed929f73A960582,
            tokens: tokens
        });

        uint256[] memory AA = new uint256[](2);
        AA[0] = 10**12;
        AA[1] = 10**12;

        QuickPulseStrategyV2.MutableParams memory smParams = QuickPulseStrategyV2.MutableParams({
            priceImpactD6: 0,
            defaultIntervalWidth: 4200,
            maxPositionLengthInTicks: 15000,
            maxDeviationForVaultPool: 50,
            timespanForAverageTick: 300,
            neighborhoodFactorD: 10 ** 7 * 15,
            extensionFactorD: 10 ** 7 * 175,
            swapSlippageD: 10 ** 7,
            swappingAmountsCoefficientD: 10 ** 7,
            minSwapAmounts: AA
        });

        QuickPulseStrategyV2.DesiredAmounts memory smsParams = QuickPulseStrategyV2.DesiredAmounts({
            amount0Desired: 10**9,
            amount1Desired: 10**9
        });

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        strategy.initialize(sParams, deployer);
        strategy.updateMutableParams(smParams);
        strategy.updateDesiredAmounts(smsParams);

        address[] memory AD = new address[](2);
        AD[0] = deployer;
        AD[1] = wrapper;

        rootVault.addDepositorsToAllowlist(AD);

        bytes32 ADMIN_ROLE =
        bytes32(0xf23ec0bb4210edd5cba85afd05127efcd2fc6a781bfed49188da1081670b22d8); // keccak256("admin)
        bytes32 ADMIN_DELEGATE_ROLE =
            bytes32(0xc171260023d22a25a00a2789664c9334017843b831138c8ef03cc8897e5873d7); // keccak256("admin_delegate")
        bytes32 OPERATOR_ROLE =
            bytes32(0x46a52cf33029de9f84853745a87af28464c80bf0346df1b32e205fc73319f622); // keccak256("operator")

        strategy.grantRole(ADMIN_ROLE, sAdmin);
        strategy.grantRole(ADMIN_DELEGATE_ROLE, sAdmin);
        strategy.grantRole(ADMIN_DELEGATE_ROLE, deployer);
        strategy.grantRole(OPERATOR_ROLE, sAdmin);
        strategy.revokeRole(ADMIN_DELEGATE_ROLE, deployer);
        strategy.revokeRole(ADMIN_ROLE, deployer);

        console2.log("strategy:", address(strategy));
        console2.log("root vault:", address(rootVault));
        console2.log("erc20 vault:", address(erc20Vault));
        console2.log("quick vault:", address(quickVault));

        return erc20VaultNft;
    }

    function run() external {
        vm.startBroadcast();

        uint256 erc20VaultNft = kek();
        

      //  rootVault = IERC20RootVault(0xAd9DF50455e690Fd2044Fd079348a1df672617B7);

        IERC20(weth).transfer(address(strategy), 10**12);
        IERC20(bob).transfer(address(strategy), 10**12);

    //    rootVault = IERC20RootVault(0x5Fd7eA4e9F96BBBab73D934618a75746Fd88e460);

        IERC20(weth).approve(address(rootVault), 10**20);
        IERC20(bob).approve(address(rootVault), 10**20);

        uint256[] memory A = new uint256[](2);
        A[0] = 10**10;
        A[1] = 10**10;

        rootVault.deposit(A, 0, "");

        A = new uint256[](2);
        A[0] = 10**15;
        A[1] = 10**15;

        rootVault.deposit(A, 0, "");

        address[] memory AD = new address[](1);
        AD[0] = deployer;

        rootVault.removeDepositorsFromAllowlist(AD);

        IVaultRegistry(registry).transferFrom(deployer, sAdmin, erc20VaultNft + 2);


        //kek();
    }
}