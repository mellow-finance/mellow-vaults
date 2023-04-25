/*

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/utils/CamelotHelper.sol";
import "../../src/MockOracle.sol";
import "../../src/MockRouter.sol";

import "../../src/vaults/CamelotVaultGovernance.sol";
import "../../src/strategies/KyberPulseStrategy.sol";

import "../../src/interfaces/external/kyber/periphery/helpers/TicksFeeReader.sol";

import "../../src/interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../../src/interfaces/vaults/IERC20VaultGovernance.sol";
import "../../src/interfaces/vaults/IKyberVaultGovernance.sol";

import "../../src/interfaces/vaults/IERC20RootVault.sol";
import "../../src/interfaces/vaults/IERC20Vault.sol";
import "../../src/interfaces/vaults/IKyberVault.sol";

import "../../src/vaults/KyberVault.sol";

contract KyberStrategyTest is Test {

    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    IKyberVault kyberVault;

    KyberPulseStrategy kyberStrategy;

    uint256 nftStart;
    address sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address admin = 0xdbA69aa8be7eC788EF5F07Ce860C631F5395E3B1;

    address public bob = 0xB0B195aEFA3650A6908f15CdaC7D92F8a5791B0B;
    address public stmatic = 0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4;
    address public governance = 0x8Ff3148CE574B8e135130065B188960bA93799c6;
    address public registry = 0xd3D0e85F225348a2006270Daf624D8c46cAe4E1F;
    address public rootGovernance = 0xC12885af1d4eAfB8176905F16d23CD7A33D21f37;
    address public erc20Governance = 0x05164eC2c3074A4E8eA20513Fbe98790FfE930A4;
    address public mellowOracle = 0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836;

    address public knc = 0x1C954E8fe737F99f68Fa1CCda3e51ebDB291948C;
    address public usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    function firstDeposit() public {
        
        deal(stmatic, deployer, 10**10);
        deal(bob, deployer, 10**10);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10**10;
        amounts[1] = 10**10;

        IERC20(stmatic).approve(address(rootVault), type(uint256).max);
        IERC20(bob).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function deposit(uint256 amount) public {

        if (rootVault.totalSupply() == 0) {
            firstDeposit();
        }

        deal(stmatic, deployer, amount * 10**18);
        deal(bob, deployer, amount * 10**18);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount * 10**18;
        amounts[1] = amount * 10**18;

        IERC20(stmatic).approve(address(rootVault), type(uint256).max);
        IERC20(bob).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

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
        tokens[0] = stmatic;
        tokens[1] = bob;

        TicksFeesReader reader = new TicksFeesReader();

        KyberHelper kyberHelper = new KyberHelper(IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8), reader);

        {
            uint8[] memory grant = new uint8[](2);
            grant[0] = 2;
            grant[1] = 3;

            IProtocolGovernance gv = IProtocolGovernance(governance);

            vm.stopPrank();
            vm.startPrank(admin);

            gv.stagePermissionGrants(stmatic, grant);
            vm.warp(block.timestamp + 86400);
            gv.commitPermissionGrants(stmatic);

            vm.stopPrank();
            vm.startPrank(deployer);

        }

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        MockOracle mockOracle = new MockOracle();
        mockOracle.updatePrice(10187222 * 10**22);

        {

            KyberVault k = new KyberVault(IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8), IRouter(0xC1e7dFE73E1598E3910EF4C7845B68A9Ab6F4c83), kyberHelper, IOracle(address(mockOracle)));

            IVaultGovernance.InternalParams memory paramsA = IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(0x8Ff3148CE574B8e135130065B188960bA93799c6),
                registry: vaultRegistry,
                singleton: k
            });

            IKyberVaultGovernance kyberVaultGovernance = new KyberVaultGovernance(paramsA);

            {

                uint8[] memory grant2 = new uint8[](1);

                IProtocolGovernance gv = IProtocolGovernance(governance);

                vm.stopPrank();
                vm.startPrank(admin);

                gv.stagePermissionGrants(address(kyberVaultGovernance), grant2);
                vm.warp(block.timestamp + 86400);
                gv.commitPermissionGrants(address(kyberVaultGovernance));

                vm.stopPrank();
                vm.startPrank(deployer);

            }

            vm.stopPrank();
            vm.startPrank(admin);

            bytes[] memory P = new bytes[](1);
            P[0] = abi.encodePacked(knc, uint24(1000), usdc, uint24(8), bob);

            IKyberVaultGovernance.StrategyParams memory paramsC = IKyberVaultGovernance.StrategyParams({
                farm: IKyberSwapElasticLM(0xBdEc4a045446F583dc564C0A227FFd475b329bf0),
                paths: P,
                pid: 117
            });

            vm.stopPrank();
            vm.startPrank(deployer);

            kyberVaultGovernance.createVault(tokens, deployer, 1000);

            kyberVaultGovernance.setStrategyParams(erc20VaultNft + 1, paramsC);
        }

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));
        kyberVault = IKyberVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        kyberStrategy = new KyberPulseStrategy(IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8));

        MockRouter mockRouter = new MockRouter(tokens, mockOracle);

        address W = 0x6243288C527c15A7B7eD6B892Bc2670E05c951F0;

        vm.stopPrank();
        vm.startPrank(admin);

        IProtocolGovernance(governance).stageValidator(address(mockRouter), W);
        IProtocolGovernance(governance).stageValidator(stmatic, W);
        IProtocolGovernance(governance).stageValidator(bob, W);
        vm.warp(block.timestamp + 86400);
        IProtocolGovernance(governance).commitValidator(address(mockRouter));
        IProtocolGovernance(governance).commitValidator(stmatic);
        IProtocolGovernance(governance).commitValidator(bob);

        vm.stopPrank();
        vm.startPrank(deployer);

        KyberPulseStrategy.ImmutableParams memory sParams = KyberPulseStrategy.ImmutableParams({
            router: address(mockRouter),
            erc20Vault: erc20Vault,
            kyberVault: kyberVault,
            mellowOracle: mockOracle,
            tokens: tokens
        });

        uint256[] memory AA = new uint256[](2);
        AA[0] = 10**15;
        AA[1] = 10**15;

        KyberPulseStrategy.MutableParams memory smParams = KyberPulseStrategy.MutableParams({
            priceImpactD6: 0,
            intervalWidth: 2400,
            tickNeighborhood: 200,
            maxDeviationForVaultPool: 50,
            amount0Desired: 10 ** 9,
            amount1Desired: 10 ** 9,
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

        deal(stmatic, address(kyberStrategy), 10**9);
        deal(bob, address(kyberStrategy), 10**9);

        deal(stmatic, address(mockRouter), 10**25);
        deal(bob, address(mockRouter), 10**25);
    }

    function isClose(uint256 x, uint256 y, uint256 measure) public returns (bool) {
        uint256 delta;
        if (x < y) {
            delta = y - x;
        }
        else {
            delta = x - y;
        }

        delta = delta * measure;
        if (delta <= x || delta <= y) {
            return true;
        }
        return false;
    }

    function setUp() external {

        vm.startPrank(deployer);

        uint256 startNft = kek();
    }

    function testRebalance() public {
        firstDeposit();
        deposit(1000);

        bytes4 selector = MockRouter.swap.selector;

        uint256 tokenIn = 0;
        uint256 amount = 50000740895733757102;

        bytes memory swapdata = abi.encodePacked(selector, tokenIn, amount);

        kyberStrategy.rebalance(block.timestamp + 1, swapdata);
    }
}

*/