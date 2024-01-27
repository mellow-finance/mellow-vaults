// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import "../../src/strategies/BaseAmmStrategy.sol";

import "../../src/test/MockRouter.sol";

import "../../src/utils/VeloDepositWrapper.sol";
import "../../src/utils/VeloHelper.sol";
import "../../src/utils/VeloFarm.sol";
import "../../src/utils/BaseAmmStrategyHelper.sol";

import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/vaults/VeloVault.sol";
import "../../src/vaults/VeloVaultGovernance.sol";

import "../../src/adapters/VeloAdapter.sol";

import "../../src/strategies/PulseOperatorStrategy.sol";

import {SwapRouter, ISwapRouter} from "./contracts/periphery/SwapRouter.sol";

contract Unit is Test {
    using SafeERC20 for IERC20;

    uint256 public constant Q96 = 2**96;
    int24 public constant TICK_SPACING = 200;

    address public protocolTreasury = address(bytes20(keccak256("treasury-1")));
    address public strategyTreasury = address(bytes20(keccak256("treasury-2")));
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public protocolAdmin = 0xAe259ed3699d1416840033ABAf92F9dD4534b2DC;

    uint256 public protocolFeeD9 = 1e8; // 10%

    address public weth = 0x4200000000000000000000000000000000000006;
    address public usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    address public velo = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db;

    address public governance = 0x6CeFdD08d633c4A92380E8F6217238bE2bd1d841;
    address public registry = 0x5cC7Cb6fD996dD646cF613ac94E9E0D2436a083A;
    address public allowAllValidator = 0x0f4A979597E16ec87d2344fD78c2cec53f37D263;
    address public mellowOracle = 0xA9FC72eE105D43C885E48Ab18148D308A55d04c7;

    IERC20RootVaultGovernance public rootVaultGovernance =
        IERC20RootVaultGovernance(0x65a440a89824AB464d7c94B184eF494c1457258D);
    IERC20VaultGovernance public erc20Governance = IERC20VaultGovernance(0xb55ef318B5F73414c91201Af4F467b6c5fE73Ece);

    ICLPool public pool = ICLPool(0xC358c95b146E9597339b376063A2cB657AFf84eb);
    ICLGauge public gauge = ICLGauge(0x5f090Fc694aa42569aB61397E4c996E808f0BBf2);
    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0xd557d3b47D159EB3f9B48c0f1B4a6e67e82e8B3f);
    SwapRouter public swapRouter = new SwapRouter(positionManager.factory(), weth);

    VeloAdapter public adapter = new VeloAdapter(positionManager);
    VeloHelper public veloHelper = new VeloHelper(positionManager);
    VeloDepositWrapper public depositWrapper = new VeloDepositWrapper(deployer);

    BaseAmmStrategy public strategy = new BaseAmmStrategy();
    PulseOperatorStrategy public operatorStrategy = new PulseOperatorStrategy();
    BaseAmmStrategyHelper public baseAmmStrategyHelper = new BaseAmmStrategyHelper();

    IVeloVaultGovernance public ammGovernance;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IVeloVault public ammVault1;
    IVeloVault public ammVault2;

    VeloFarm public farm;

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

        {
            address[] memory whitelist = new address[](1);
            whitelist[0] = address(depositWrapper);
            rootVault.addDepositorsToAllowlist(whitelist);
        }

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

    function deployVaults() public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = usdc;

        erc20Governance.createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        ammGovernance.createVault(tokens, deployer, TICK_SPACING);
        ammVault1 = IVeloVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        ammGovernance.createVault(tokens, deployer, TICK_SPACING);
        ammVault2 = IVeloVault(vaultRegistry.vaultForNft(erc20VaultNft + 2));

        farm = new VeloFarm();

        ammGovernance.setStrategyParams(
            erc20VaultNft + 1,
            IVeloVaultGovernance.StrategyParams({farm: address(farm), gauge: address(gauge)})
        );
        ammGovernance.setStrategyParams(
            erc20VaultNft + 2,
            IVeloVaultGovernance.StrategyParams({farm: address(farm), gauge: address(gauge)})
        );

        {
            uint256[] memory nfts = new uint256[](3);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            nfts[2] = erc20VaultNft + 2;
            combineVaults(tokens, nfts);
        }

        farm.initialize(
            address(rootVault),
            address(deployer),
            address(protocolTreasury),
            address(gauge.rewardToken()),
            protocolFeeD9
        );
    }

    function deployGovernance() public {
        VeloVault singleton = new VeloVault(positionManager, veloHelper);
        ammGovernance = new VeloVaultGovernance(
            IVaultGovernance.InternalParams({
                singleton: singleton,
                registry: IVaultRegistry(registry),
                protocolGovernance: IProtocolGovernance(governance)
            })
        );

        vm.stopPrank();
        vm.startPrank(protocolAdmin);

        IProtocolGovernance(governance).stagePermissionGrants(address(ammGovernance), new uint8[](1));
        uint8[] memory permissions = new uint8[](1);
        permissions[0] = 4;
        IProtocolGovernance(governance).stagePermissionGrants(address(swapRouter), permissions);
        IProtocolGovernance(governance).stageValidator(address(swapRouter), allowAllValidator);

        skip(24 * 3600);
        IProtocolGovernance(governance).commitPermissionGrants(address(ammGovernance));
        IProtocolGovernance(governance).commitPermissionGrants(address(swapRouter));
        IProtocolGovernance(governance).commitValidator(address(swapRouter));

        vm.stopPrank();
        vm.startPrank(deployer);
    }

    function initializeBaseStrategy() public {
        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e9;
        minSwapAmounts[1] = 1e3;

        IIntegrationVault[] memory ammVaults = new IIntegrationVault[](2);
        ammVaults[0] = ammVault1;
        ammVaults[1] = ammVault2;

        strategy.initialize(
            deployer,
            BaseAmmStrategy.ImmutableParams({
                erc20Vault: erc20Vault,
                ammVaults: ammVaults,
                adapter: adapter,
                pool: address(ammVault1.pool())
            }),
            BaseAmmStrategy.MutableParams({
                securityParams: new bytes(0),
                maxPriceSlippageX96: (2 * Q96) / 100,
                maxTickDeviation: 50,
                minCapitalRatioDeviationX96: Q96 / 100,
                minSwapAmounts: minSwapAmounts,
                maxCapitalRemainderRatioX96: Q96 / 50,
                initialLiquidity: 1e9
            })
        );
    }

    function deposit(uint256 coef) public {
        uint256 totalSupply = rootVault.totalSupply();
        uint256[] memory tokenAmounts = rootVault.pullExistentials();
        address[] memory tokens = rootVault.vaultTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] *= 10 * coef;
            deal(tokens[i], deployer, tokenAmounts[i]);
        }
        if (totalSupply == 0) {
            for (uint256 i = 0; i < tokens.length; i++) {
                IERC20(tokens[i]).approve(address(depositWrapper), type(uint256).max);
            }
            depositWrapper.addNewStrategy(address(rootVault), address(farm), address(strategy), false);
        } else {
            depositWrapper.addNewStrategy(address(rootVault), address(farm), address(strategy), true);
        }
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
    }

    function initializeOperatorStrategy(int24 maxWidth) public {
        operatorStrategy.initialize(
            PulseOperatorStrategy.ImmutableParams({strategy: strategy, tickSpacing: pool.tickSpacing()}),
            PulseOperatorStrategy.MutableParams({
                positionWidth: 200,
                maxPositionWidth: maxWidth,
                extensionFactorD: 1e9,
                neighborhoodFactorD: 1e8
            }),
            deployer
        );
        strategy.grantRole(strategy.ADMIN_DELEGATE_ROLE(), address(deployer));
        strategy.grantRole(strategy.OPERATOR(), address(operatorStrategy));

        deal(usdc, address(strategy), 1e7);
        deal(weth, address(strategy), 1e16);
    }

    function rebalance() public {
        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
        BaseAmmStrategy.Position[] memory target = new BaseAmmStrategy.Position[](2);
        (BaseAmmStrategy.Position memory newPosition, ) = operatorStrategy.calculateExpectedPosition();
        target[0].tickLower = newPosition.tickLower;
        target[0].tickUpper = newPosition.tickUpper;
        target[0].capitalRatioX96 = Q96;
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 expectedAmountOut) = baseAmmStrategyHelper
            .calculateSwapAmounts(sqrtPriceX96, target, rootVault, 3000);
        uint256 amountOutMin = (expectedAmountOut * 99) / 100;
        bytes memory data = abi.encodeWithSelector(
            ISwapRouter.exactInputSingle.selector,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: TICK_SPACING,
                amountIn: amountIn,
                deadline: type(uint256).max,
                recipient: address(erc20Vault),
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );

        operatorStrategy.rebalance(
            BaseAmmStrategy.SwapData({
                router: address(swapRouter),
                data: data,
                tokenInIndex: tokenIn < tokenOut ? 0 : 1,
                amountIn: amountIn,
                amountOutMin: amountOutMin
            })
        );
    }

    function _swapAmount(uint256 amountIn, uint256 tokenInIndex) private {
        if (amountIn == 0) revert("Insufficient amount for swap");
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = usdc;
        address tokenIn = tokens[tokenInIndex];
        address tokenOut = tokens[tokenInIndex ^ 1];
        deal(tokenIn, deployer, amountIn);
        IERC20(tokenIn).safeIncreaseAllowance(address(swapRouter), amountIn);
        ISwapRouter(swapRouter).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: TICK_SPACING,
                recipient: deployer,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0,
                deadline: type(uint256).max
            })
        );
        skip(24 * 3600);
    }

    function movePrice(int24 targetTick) public {
        int24 spotTick;
        (, spotTick, , , , ) = pool.slot0();
        uint256 usdcAmount = IERC20(usdc).balanceOf(address(pool));
        uint256 wethAmount = IERC20(weth).balanceOf(address(pool));
        if (spotTick < targetTick) {
            while (spotTick < targetTick) {
                _swapAmount(usdcAmount, 1);
                (, spotTick, , , , ) = pool.slot0();
            }
        } else {
            while (spotTick > targetTick) {
                _swapAmount(wethAmount, 0);
                (, spotTick, , , , ) = pool.slot0();
            }
        }

        while (spotTick != targetTick) {
            if (spotTick < targetTick) {
                while (spotTick < targetTick) {
                    _swapAmount(usdcAmount, 1);
                    (, spotTick, , , , ) = pool.slot0();
                }
                usdcAmount >>= 1;
            } else {
                while (spotTick > targetTick) {
                    _swapAmount(wethAmount, 0);
                    (, spotTick, , , , ) = pool.slot0();
                }
                wethAmount >>= 1;
            }
        }
    }

    function addLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public {
        (uint160 sqrtRatioX96, , , , , ) = pool.slot0();
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );
        deal(weth, address(adapter), amount0 * 2);
        deal(usdc, address(adapter), amount1 * 2);
        adapter.mint(address(pool), tickLower, tickUpper, liquidity, address(adapter));
    }

    function normalizePool() public {
        pool.increaseObservationCardinalityNext(2);
        {
            int24 lowerTick = -800000;
            int24 upperTick = 800000;
            addLiquidity(lowerTick, upperTick, 2500 ether);
        }

        (, int24 targetTick, , , , , ) = IUniswapV3Pool(0x85149247691df622eaF1a8Bd0CaFd40BC45154a9).slot0();

        _swapAmount(2621439999999999988840005632, 0);
        movePrice(targetTick);

        targetTick -= targetTick % TICK_SPACING;

        {
            (uint160 sqrtRatioX96, , , , , ) = pool.slot0();
            uint256 priceX96 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, Q96);
            uint256 usdcAmount = 5e12;
            uint256 wethAmount = FullMath.mulDiv(usdcAmount, Q96, priceX96);

            for (int24 i = 1; i <= 20; i++) {
                int24 lowerTick = targetTick - i * TICK_SPACING;
                int24 upperTick = targetTick + i * TICK_SPACING;
                uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                    sqrtRatioX96,
                    TickMath.getSqrtRatioAtTick(lowerTick),
                    TickMath.getSqrtRatioAtTick(upperTick),
                    wethAmount,
                    usdcAmount
                );
                addLiquidity(lowerTick, upperTick, liquidity);
            }
        }

        skip(3 * 24 * 3600);
    }

    function setUp() external {
        vm.startPrank(deployer);

        normalizePool();

        deployGovernance();
        deployVaults();
        initializeBaseStrategy();
        initializeOperatorStrategy(200);
        deposit(1);
        rebalance();
        deposit(1e7);

        vm.stopPrank();
    }

    // TODO:
    function testInitialize() external {}
}
