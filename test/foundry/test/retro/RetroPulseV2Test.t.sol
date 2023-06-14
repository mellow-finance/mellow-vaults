// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/interfaces/external/univ3/ISwapRouter.sol";

import "../../src/strategies/PulseStrategyV2.sol";

import "../../src/test/MockRouter.sol";

import "../../src/utils/DepositWrapper.sol";
import "../../src/utils/UniV3Helper.sol";
import "../../src/utils/PulseStrategyV2Helper.sol";

import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/vaults/UniV3Vault.sol";
import "../../src/vaults/UniV3VaultGovernance.sol";

contract RetroPulseV2Test is Test {
    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault;

    uint256 public nftStart;
    address public sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address public protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address public strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address public admin = 0xdbA69aa8be7eC788EF5F07Ce860C631F5395E3B1;

    address public usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    address public governance = 0x8Ff3148CE574B8e135130065B188960bA93799c6;
    address public registry = 0xd3D0e85F225348a2006270Daf624D8c46cAe4E1F;
    address public rootGovernance = 0xC12885af1d4eAfB8176905F16d23CD7A33D21f37;
    address public erc20Governance = 0x05164eC2c3074A4E8eA20513Fbe98790FfE930A4;
    address public mellowOracle = 0x27AeBFEBDd0fde261Ec3E1DF395061C56EEC5836;

    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0x7ae5c1f17dfa691b4be311Db5562feF117a0e2Fd);

    address public swapRouter = 0x6bF1Fb7cf91D62A6c15a889Ff123Cc58E0ea4F60;

    UniV3VaultGovernance public uniV3VaultGovernance;
    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    PulseStrategyV2 public strategy = new PulseStrategyV2(positionManager);
    DepositWrapper public depositWrapper = new DepositWrapper(deployer);
    MockRouter public router = new MockRouter();

    PulseStrategyV2Helper public strategyHelper = new PulseStrategyV2Helper();
    UniV3Helper public vaultHelper = new UniV3Helper(positionManager);

    uint256 public constant Q96 = 2**96;

    function firstDeposit() public {
        deal(usdc, deployer, 10**4);
        deal(wmatic, deployer, 10**13);

        uint256[] memory tokenAmounts = new uint256[](2);

        tokenAmounts[0] = 10**13;
        tokenAmounts[1] = 10**4;

        vm.startPrank(deployer);
        IERC20(usdc).approve(address(depositWrapper), type(uint256).max);
        IERC20(wmatic).approve(address(depositWrapper), type(uint256).max);

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);

        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));

        vm.stopPrank();
    }

    function deposit() public {
        deal(usdc, deployer, 1e10);
        deal(wmatic, deployer, 1e18 * 1e4);

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 1e18 * 1e4;
        tokenAmounts[1] = 1e10;

        vm.startPrank(deployer);
        (, bool needToCallCallback) = depositWrapper.depositInfo(address(rootVault));
        if (!needToCallCallback) {
            depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
        }

        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
        vm.stopPrank();
    }

    function withdraw() public {
        vm.startPrank(deployer);
        uint256 lpAmount = rootVault.balanceOf(deployer) / 2;
        rootVault.withdraw(deployer, lpAmount, new uint256[](2), new bytes[](2));
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
        tokens[0] = wmatic;
        tokens[1] = usdc;
        vm.startPrank(deployer);
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IUniV3VaultGovernance(uniV3VaultGovernance).createVault(tokens, deployer, 500, address(vaultHelper));

        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));
        uniV3VaultGovernance.stageDelayedStrategyParams(
            erc20VaultNft + 1,
            IUniV3VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );

        uniV3VaultGovernance.commitDelayedStrategyParams(erc20VaultNft + 1);

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }
        vm.stopPrank();
    }

    function deployGovernances() public {
        uniV3VaultGovernance = new UniV3VaultGovernance(
            IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: IVaultRegistry(registry),
                singleton: IVault(address(new UniV3Vault()))
            }),
            IUniV3VaultGovernance.DelayedProtocolParams({
                positionManager: positionManager,
                oracle: IOracle(mellowOracle)
            })
        );

        vm.startPrank(admin);
        IProtocolGovernance(governance).stagePermissionGrants(address(uniV3VaultGovernance), new uint8[](1));
        uint8[] memory permission = new uint8[](1);
        permission[0] = 4;
        IProtocolGovernance(governance).stagePermissionGrants(address(router), permission);
        permission = new uint8[](2);
        permission[0] = 2;
        permission[1] = 3;
        IProtocolGovernance(governance).stagePermissionGrants(wmatic, permission);
        IProtocolGovernance(governance).stageValidator(address(router), 0x6243288C527c15A7B7eD6B892Bc2670E05c951F0);
        IProtocolGovernance(governance).stageValidator(wmatic, 0x76787742E9E56479Bf9f6de6C16EBf1Ff58478e8);
        IProtocolGovernance(governance).stageUnitPrice(wmatic, 1e18);

        skip(24 * 3600);

        IProtocolGovernance(governance).commitPermissionGrants(address(uniV3VaultGovernance));
        IProtocolGovernance(governance).commitPermissionGrants(address(router));
        IProtocolGovernance(governance).commitPermissionGrants(wmatic);
        IProtocolGovernance(governance).commitValidator(address(router));
        IProtocolGovernance(governance).commitValidator(wmatic);
        IProtocolGovernance(governance).commitUnitPrice(wmatic);

        vm.stopPrank();
    }

    function initializeStrategy() public {
        vm.startPrank(sAdmin);

        strategy.initialize(
            PulseStrategyV2.ImmutableParams({
                erc20Vault: erc20Vault,
                uniV3Vault: uniV3Vault,
                router: address(router),
                tokens: erc20Vault.vaultTokens()
            }),
            sAdmin
        );

        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 5e15;
        minSwapAmounts[1] = 1e6;

        strategy.updateMutableParams(
            PulseStrategyV2.MutableParams({
                priceImpactD6: 0,
                defaultIntervalWidth: 4200,
                maxPositionLengthInTicks: 10000,
                maxDeviationForVaultPool: 100,
                timespanForAverageTick: 30,
                neighborhoodFactorD: 1e9,
                extensionFactorD: 1e8,
                swapSlippageD: 1e7,
                swappingAmountsCoefficientD: 1e7,
                minSwapAmounts: minSwapAmounts
            })
        );

        strategy.updateDesiredAmounts(PulseStrategyV2.DesiredAmounts({amount0Desired: 1e6, amount1Desired: 1e9}));

        deal(usdc, address(strategy), 10**8);
        deal(wmatic, address(strategy), 10**11);

        vm.stopPrank();
    }

    function rebalance() public {
        (uint256 amountIn, address tokenIn, address tokenOut, IERC20Vault reciever) = strategyHelper
            .calculateAmountForSwap(strategy);

        deal(usdc, address(router), type(uint128).max);
        deal(wmatic, address(router), type(uint128).max);

        (uint160 sqrtPriceX96, , , , , , ) = uniV3Vault.pool().slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (tokenIn == usdc) priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);

        router.setPrice(priceX96);

        uint256 expectedAmountOut = FullMath.mulDiv(amountIn, priceX96, 2**96);
        expectedAmountOut = FullMath.mulDiv(expectedAmountOut, 99, 100);

        bytes memory swapData = abi.encodeWithSelector(router.swap.selector, amountIn, tokenIn, tokenOut, reciever);

        vm.startPrank(sAdmin);
        strategy.rebalance(type(uint256).max, swapData, expectedAmountOut);
        vm.stopPrank();
    }

    function movePrice(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public {
        vm.startPrank(deployer);
        deal(tokenIn, deployer, amountIn);
        IERC20(tokenIn).approve(swapRouter, amountIn);
        ISwapRouter(swapRouter).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 500,
                recipient: deployer,
                deadline: type(uint256).max,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        skip(24 * 3600);
        vm.stopPrank();
    }

    function logState() public view {
        uint256 nft = uniV3Vault.uniV3Nft();
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = positionManager.positions(nft);

        (uint256[] memory tvl, ) = rootVault.tvl();
        (uint256[] memory erc20Tvl, ) = erc20Vault.tvl();
        (uint256[] memory uniswapTvl, ) = uniV3Vault.tvl();

        console2.log("Position:", uint24(tickLower), uint24(tickUpper));
        console2.log("RootVault tvl wmatic / usdc :", tvl[0], tvl[1]);
        console2.log("ERC20Vault tvl wmatic / usdc :", erc20Tvl[0], erc20Tvl[1]);
        console2.log("UniV3Vault tvl wmatic / usdc :", uniswapTvl[0], uniswapTvl[1]);
        console2.log();
    }

    function createPool() public {
        vm.startPrank(deployer);

        IUniswapV3Factory factory = IUniswapV3Factory(positionManager.factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(usdc, wmatic, 500));

        pool.initialize(TickMath.getSqrtRatioAtTick(-280564));
        pool.increaseObservationCardinalityNext(12);

        deal(usdc, deployer, 1e12);
        deal(wmatic, deployer, 1e21);

        IERC20(usdc).approve(address(positionManager), type(uint256).max);
        IERC20(wmatic).approve(address(positionManager), type(uint256).max);

        positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: wmatic,
                token1: usdc,
                fee: 500,
                tickLower: -280500 - 1000,
                tickUpper: -280500 + 1000,
                amount0Desired: 1e18 * 10,
                amount1Desired: 1e9,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: type(uint256).max
            })
        );

        vm.stopPrank();

        movePrice(usdc, wmatic, 1e9);
        movePrice(wmatic, usdc, 1e18);
    }

    function testDeposit() external {
        createPool();
        deployGovernances();
        deployVaults();
        firstDeposit();
        initializeStrategy();
        rebalance();
        deposit();
    }

    function testStrategy() external {
        createPool();

        deployGovernances();
        deployVaults();
        firstDeposit();
        initializeStrategy();
        rebalance();
        deposit();
        rebalance();
        deposit();
        rebalance();
        deposit();
        withdraw();
        rebalance();
        deposit();
        withdraw();

        logState();

        for (uint256 i = 0; i < 5; i++) {
            movePrice(usdc, wmatic, 1e6 * 1e3);
            rebalance();
            logState();
        }

        for (uint256 i = 0; i < 5; i++) {
            movePrice(wmatic, usdc, 1e18 * 1e3);
            rebalance();
            logState();
        }
    }
}
