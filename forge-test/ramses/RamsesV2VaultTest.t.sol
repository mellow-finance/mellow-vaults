// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "../../src/test/MockRouter.sol";

import "../../src/utils/StakingDepositWrapper.sol";
import "../../src/utils/RamsesV2Helper.sol";

import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/vaults/RamsesV2Vault.sol";
import "../../src/vaults/RamsesV2VaultGovernance.sol";

import "../../src/strategies/GRamsesStrategy.sol";

contract RamsesV2VaultTest is Test {
    using SafeERC20 for IERC20;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IRamsesV2Vault public lowerVault;
    IRamsesV2Vault public upperVault;

    address public ramsesRouter = 0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13;

    address public grai = 0x894134a25a5faC1c2C26F1d8fBf05111a3CB9487;
    address public lusd = 0x93b346b6BC2548dA6A1E7d98E9a421B42541425b;

    address public sAdmin = 0x49e99fd160a04304b6CFd251Fce0ACB0A79c626d;
    address public protocolTreasury = 0xDF6780faC92ec8D5f366584c29599eA1c97C77F5;
    address public strategyTreasury = 0xb0426fDFEfF47B23E5c2794D406A3cC8E77Ec001;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public admin = 0x160cda72DEc5E7ECc82E0a98CF13c29B0a2396E4;

    address public governance = 0x65a440a89824AB464d7c94B184eF494c1457258D;
    address public registry = 0x7D7fEF7bF8bE4DB0FFf06346C59efc24EE8e4c22;
    address public rootGovernance = 0xC75825C5539968648632ec6207f8EDeC407dF891;
    address public erc20Governance = 0x7D62E2c0516B8e747d95323Ca350c847C4Dea533;
    address public mellowOracle = 0x3EFf1DA9e5f72d51F268937d3A5426c2bf5eFf4A;

    address public erc20Validator = 0xa3420E55cC602a65bFA114A955DB1B1D4CA03745;

    IRamsesV2NonfungiblePositionManager public positionManager =
        IRamsesV2NonfungiblePositionManager(0xAA277CB7914b7e5514946Da92cb9De332Ce610EF);
    RamsesV2VaultGovernance public ramsesGovernance;
    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    StakingDepositWrapper public depositWrapper = new StakingDepositWrapper(deployer);
    RamsesV2Helper public vaultHelper = new RamsesV2Helper(positionManager);

    GRamsesStrategy public strategy = new GRamsesStrategy(positionManager);

    uint256 public constant Q96 = 2**96;
    address[] public rewards;
    InstantFarm public lpFarm;

    function deposit(bool flag) public {
        deal(lusd, deployer, 100 ether);
        deal(grai, deployer, 100 ether);

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = flag ? 10 ether : 1e15;
        tokenAmounts[1] = flag ? 10 ether : 1e15;

        vm.startPrank(deployer);
        IERC20(lusd).approve(address(depositWrapper), type(uint256).max);
        IERC20(grai).approve(address(depositWrapper), type(uint256).max);

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), flag);
        depositWrapper.deposit(rootVault, lpFarm, tokenAmounts, 0, new bytes(0));

        vm.stopPrank();
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        uint256 nft;
        (rootVault, nft) = rootVaultGovernance.createVault(tokens, address(strategy), nfts, deployer);
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

    function deployVaults() public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = grai;
        tokens[1] = lusd;
        vm.startPrank(deployer);
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        ramsesGovernance.createVault(tokens, deployer, 500, address(vaultHelper), address(erc20Vault));
        lowerVault = IRamsesV2Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));
        ramsesGovernance.setStrategyParams(
            lowerVault.nft(),
            IRamsesV2VaultGovernance.StrategyParams({
                farm: address(lpFarm),
                rewards: rewards,
                gaugeV2: address(0x8cfBc79E06A80f5931B3F9FCC4BbDfac91D45A50)
            })
        );
        ramsesGovernance.stageDelayedStrategyParams(
            lowerVault.nft(),
            IRamsesV2VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );
        ramsesGovernance.commitDelayedStrategyParams(lowerVault.nft());

        ramsesGovernance.createVault(tokens, deployer, 500, address(vaultHelper), address(erc20Vault));
        upperVault = IRamsesV2Vault(vaultRegistry.vaultForNft(erc20VaultNft + 2));
        ramsesGovernance.setStrategyParams(
            upperVault.nft(),
            IRamsesV2VaultGovernance.StrategyParams({
                farm: address(lpFarm),
                rewards: rewards,
                gaugeV2: address(0x8cfBc79E06A80f5931B3F9FCC4BbDfac91D45A50)
            })
        );
        ramsesGovernance.stageDelayedStrategyParams(
            upperVault.nft(),
            IRamsesV2VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );
        ramsesGovernance.commitDelayedStrategyParams(upperVault.nft());

        {
            uint256[] memory nfts = new uint256[](3);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            nfts[2] = erc20VaultNft + 2;
            combineVaults(tokens, nfts);
        }

        lpFarm = new InstantFarm(address(rootVault), deployer, rewards);
        vm.stopPrank();
    }

    function deployGovernances() public {
        rewards = new address[](2);
        rewards[0] = 0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418;
        rewards[1] = 0xAAA1eE8DC1864AE49185C368e8c64Dd780a50Fb7;

        ramsesGovernance = new RamsesV2VaultGovernance(
            IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: IVaultRegistry(registry),
                singleton: IVault(address(new RamsesV2Vault()))
            }),
            IRamsesV2VaultGovernance.DelayedProtocolParams({
                positionManager: positionManager,
                oracle: IOracle(mellowOracle)
            })
        );

        uint8[] memory tokenPermissions = new uint8[](2);
        tokenPermissions[0] = 2;
        tokenPermissions[1] = 3;

        vm.startPrank(admin);

        IProtocolGovernance(governance).stagePermissionGrants(address(ramsesGovernance), new uint8[](1));
        IProtocolGovernance(governance).stagePermissionGrants(address(lusd), tokenPermissions);
        IProtocolGovernance(governance).stagePermissionGrants(address(grai), tokenPermissions);
        IProtocolGovernance(governance).stageValidator(address(grai), erc20Validator);
        IProtocolGovernance(governance).stageValidator(address(lusd), erc20Validator);

        skip(24 * 3600);

        IProtocolGovernance(governance).commitPermissionGrants(address(ramsesGovernance));
        IProtocolGovernance(governance).commitPermissionGrants(address(lusd));
        IProtocolGovernance(governance).commitPermissionGrants(address(grai));
        IProtocolGovernance(governance).commitValidator(address(grai));
        IProtocolGovernance(governance).commitValidator(address(lusd));

        vm.stopPrank();
    }

    // function emulateStrategy() public {
    //     vm.startPrank(deployer);

    //     deal(grai, deployer, 100 ether);
    //     deal(lusd, deployer, 100 ether);

    //     IERC20(grai).safeApprove(address(positionManager), type(uint256).max);
    //     IERC20(lusd).safeApprove(address(positionManager), type(uint256).max);

    //     (uint256 nft, , , ) = positionManager.mint(
    //         IRamsesV2NonfungiblePositionManager.MintParams({
    //             token0: grai,
    //             token1: lusd,
    //             fee: 500,
    //             tickLower: -1000,
    //             tickUpper: 1000,
    //             recipient: deployer,
    //             deadline: type(uint256).max,
    //             amount0Desired: 1 ether,
    //             amount1Desired: 1 ether,
    //             amount0Min: 0,
    //             amount1Min: 0
    //         })
    //     );

    //     positionManager.safeTransferFrom(deployer, address(ramsesVault), nft);

    //     vm.stopPrank();
    // }

    function initializeStrategy() public {
        vm.startPrank(operator);

        deal(grai, address(strategy), 1 ether);
        deal(lusd, address(strategy), 1 ether);

        strategy.initialize(
            operator,
            GRamsesStrategy.ImmutableParams({
                fee: 500,
                pool: IRamsesV2Pool(lowerVault.pool()),
                erc20Vault: erc20Vault,
                lowerVault: lowerVault,
                upperVault: upperVault,
                router: ramsesRouter,
                tokens: lowerVault.vaultTokens()
            })
        );

        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e15;
        minSwapAmounts[1] = 1e15;

        strategy.updateMutableParams(
            GRamsesStrategy.MutableParams({
                timespan: 60,
                maxTickDeviation: 10,
                intervalWidth: 10,
                priceImpactD6: 1000, // 1%
                amount0Desired: 10 gwei,
                amount1Desired: 10 gwei,
                maxRatioDeviationX96: uint256(2**96) / 100,
                swapSlippageD: 1e7,
                swappingAmountsCoefficientD: 1e7,
                minSwapAmounts: minSwapAmounts
            })
        );

        vm.stopPrank();
    }

    function test() external {
        deployGovernances();
        deployVaults();
        initializeStrategy();
        deposit(false);

        vm.startPrank(operator);
        strategy.rebalance("", 0, type(uint256).max);
        vm.stopPrank();

        (uint256[] memory tvl, ) = rootVault.tvl();
        console2.log(tvl[0], tvl[1]);

        deposit(true);

        (tvl, ) = rootVault.tvl();
        console2.log(tvl[0], tvl[1]);
    }
}
