// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/utils/CamelotHelper.sol";
import "../../src/MockOracle.sol";
import "../../src/MockRouter.sol";

import "../../src/vaults/CamelotVaultGovernance.sol";
import {CamelotPulseStrategyV2} from "../../src/strategies/CamelotPulseStrategyV2.sol";

import "../../src/interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../../src/interfaces/vaults/IERC20VaultGovernance.sol";
import "../../src/interfaces/vaults/ICamelotVaultGovernance.sol";

import "../../src/interfaces/vaults/IERC20RootVault.sol";
import "../../src/interfaces/vaults/IERC20Vault.sol";
import "../../src/interfaces/vaults/ICamelotVault.sol";

import "../../src/vaults/CamelotVault.sol";

contract CamelotStrategyTest is Test {
    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    ICamelotVault camelotVault;

    CamelotPulseStrategyV2 camelotStrategy;

    uint256 nftStart;
    address sAdmin = 0x49e99fd160a04304b6CFd251Fce0ACB0A79c626d;
    address protocolTreasury = 0xDF6780faC92ec8D5f366584c29599eA1c97C77F5;
    address strategyTreasury = 0xb0426fDFEfF47B23E5c2794D406A3cC8E77Ec001;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address admin = 0x160cda72DEc5E7ECc82E0a98CF13c29B0a2396E4;

    address public weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    address public governance = 0x65a440a89824AB464d7c94B184eF494c1457258D;
    address public registry = 0x7D7fEF7bF8bE4DB0FFf06346C59efc24EE8e4c22;

    address public rootGovernance = 0xC75825C5539968648632ec6207f8EDeC407dF891;
    address public erc20Governance = 0x7D62E2c0516B8e747d95323Ca350c847C4Dea533;
    address public mellowOracle = 0x3EFf1DA9e5f72d51F268937d3A5426c2bf5eFf4A;

    address public manager = 0xAcDcC3C6A2339D08E0AC9f694E4DE7c52F890Db3;

    IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    function firstDeposit() public {
        deal(weth, deployer, 10 ** 10);
        deal(usdc, deployer, 10 ** 4);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10 ** 10;
        amounts[1] = 10 ** 4;

        IERC20(weth).approve(address(rootVault), type(uint256).max);
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function deposit(uint256 amount) public {
        if (rootVault.totalSupply() == 0) {
            firstDeposit();
        }

        deal(weth, deployer, amount * 10 ** 15);
        deal(usdc, deployer, amount * 10 ** 6);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount * 10 ** 15;
        amounts[1] = amount * 10 ** 6;

        IERC20(weth).approve(address(rootVault), type(uint256).max);
        IERC20(usdc).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(
            tokens,
            address(camelotStrategy),
            nfts,
            deployer
        );
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
        tokens[0] = weth;
        tokens[1] = usdc;

        CamelotHelper helper = new CamelotHelper(IAlgebraNonfungiblePositionManager(manager), weth, usdc);

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);
        }

        MockOracle mockOracle = new MockOracle();
        mockOracle.updatePrice(14832901 * 10 ** 13);

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        {
            CamelotVault k = new CamelotVault(IAlgebraNonfungiblePositionManager(manager), helper);

            IVaultGovernance.InternalParams memory paramsA = IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: vaultRegistry,
                singleton: k
            });

            ICamelotVaultGovernance camelotVaultGovernance = new CamelotVaultGovernance(paramsA);

            {
                uint8[] memory grant2 = new uint8[](1);

                IProtocolGovernance gv = IProtocolGovernance(governance);

                vm.stopPrank();
                vm.startPrank(admin);

                gv.stagePermissionGrants(address(camelotVaultGovernance), grant2);
                vm.warp(block.timestamp + 86400);
                gv.commitPermissionGrants(address(camelotVaultGovernance));

                vm.stopPrank();
                vm.startPrank(deployer);
            }

            camelotVaultGovernance.createVault(tokens, deployer, address(erc20Vault));
        }

        camelotVault = ICamelotVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        camelotStrategy = new CamelotPulseStrategyV2(IAlgebraNonfungiblePositionManager(manager));
        MockRouter mockRouter = new MockRouter(tokens, mockOracle);

        {
            uint8[] memory grant = new uint8[](1);
            grant[0] = 4;

            IProtocolGovernance gv = IProtocolGovernance(governance);

            vm.stopPrank();
            vm.startPrank(admin);

            gv.stagePermissionGrants(address(mockRouter), grant);
            vm.warp(block.timestamp + 86400);
            gv.commitPermissionGrants(address(mockRouter));

            vm.stopPrank();
            vm.startPrank(deployer);
        }

        address W = 0x52314d240BCA143aCF755870659B9035eE357bb6;

        vm.stopPrank();
        vm.startPrank(admin);

        IProtocolGovernance(governance).stageValidator(address(mockRouter), W);
        vm.warp(block.timestamp + 86400);
        IProtocolGovernance(governance).commitValidator(address(mockRouter));

        vm.stopPrank();
        vm.startPrank(deployer);

        CamelotPulseStrategyV2.ImmutableParams memory sParams = CamelotPulseStrategyV2.ImmutableParams({
            erc20Vault: erc20Vault,
            camelotVault: camelotVault,
            router: address(mockRouter),
            tokens: tokens
        });

        uint256[] memory AA = new uint256[](2);
        AA[0] = 10 ** 12;
        AA[1] = 10 ** 3;

        CamelotPulseStrategyV2.MutableParams memory smParams = CamelotPulseStrategyV2.MutableParams({
            priceImpactD6: 0,
            defaultIntervalWidth: 4200,
            maxPositionLengthInTicks: 15000,
            maxDeviationForVaultPool: 50,
            timespanForAverageTick: 300,
            neighborhoodFactorD: 15 * 10 ** 7,
            extensionFactorD: 175 * 10 ** 7,
            swapSlippageD: 10 ** 7,
            swappingAmountsCoefficientD: 10 ** 7,
            minSwapAmounts: AA
        });

        CamelotPulseStrategyV2.DesiredAmounts memory smmParams = CamelotPulseStrategyV2.DesiredAmounts({
            amount0Desired: 10 ** 9,
            amount1Desired: 10 ** 9
        });

        //   kyberVault.updateFarmInfo();

        //   preparePush(address(kyberVault));

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        camelotStrategy.initialize(sParams, deployer);
        camelotStrategy.updateMutableParams(smParams);
        camelotStrategy.updateDesiredAmounts(smmParams);

        deal(weth, address(camelotStrategy), 10 ** 9);
        deal(usdc, address(camelotStrategy), 10 ** 9);

        deal(weth, address(mockRouter), 10 ** 25);
        deal(usdc, address(mockRouter), 10 ** 25);
    }

    function isClose(uint256 x, uint256 y, uint256 measure) public returns (bool) {
        uint256 delta;
        if (x < y) {
            delta = y - x;
        } else {
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

        uint256 tokenIn = 1;
        uint256 amount = 511344429;

        bytes memory swapdata = abi.encodePacked(selector, tokenIn, amount);

        camelotStrategy.rebalance(block.timestamp + 1, swapdata, 0);
    }

    function testFailRebalanceWrongAmount() public {
        firstDeposit();
        deposit(1000);

        bytes4 selector = MockRouter.swap.selector;

        uint256 tokenIn = 1;
        uint256 amount = 51134442;

        bytes memory swapdata = abi.encodePacked(selector, tokenIn, amount);

        camelotStrategy.rebalance(block.timestamp + 1, swapdata, 0);
    }
}
