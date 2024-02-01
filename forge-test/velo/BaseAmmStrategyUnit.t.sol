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
import "../../src/utils/BaseAmmStrategyHelper.sol";

import "../../src/utils/external/synthetix/StakingRewards.sol";

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
    VeloDepositWrapper public depositWrapper = new VeloDepositWrapper(deployer, deployer);

    BaseAmmStrategy public strategy = new BaseAmmStrategy();
    PulseOperatorStrategy public operatorStrategy = new PulseOperatorStrategy();
    BaseAmmStrategyHelper public baseAmmStrategyHelper = new BaseAmmStrategyHelper();

    IVeloVaultGovernance public ammGovernance;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IVeloVault public ammVault1;
    IVeloVault public ammVault2;

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

        ammGovernance.setStrategyParams(
            erc20VaultNft + 1,
            IVeloVaultGovernance.StrategyParams({
                farmingPool: address(depositWrapper),
                gauge: address(gauge),
                protocolTreasury: protocolTreasury,
                protocolFeeD9: protocolFeeD9
            })
        );
        ammGovernance.setStrategyParams(
            erc20VaultNft + 2,
            IVeloVaultGovernance.StrategyParams({
                farmingPool: address(depositWrapper),
                gauge: address(gauge),
                protocolTreasury: protocolTreasury,
                protocolFeeD9: protocolFeeD9
            })
        );

        {
            uint256[] memory nfts = new uint256[](3);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            nfts[2] = erc20VaultNft + 2;
            combineVaults(tokens, nfts);
        }

        depositWrapper.initialize(address(rootVault), address(gauge.rewardToken()), deployer);
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
            depositWrapper.setStrategyInfo(address(strategy), false);
        } else {
            depositWrapper.setStrategyInfo(address(strategy), true);
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

    function testInitialize() external {
        BaseAmmStrategy.ImmutableParams memory immutableParams = strategy.getImmutableParams();
        BaseAmmStrategy.MutableParams memory mutableParams = strategy.getMutableParams();

        vm.expectRevert(abi.encodePacked("AZ"));
        strategy.initialize(address(0), immutableParams, mutableParams);

        vm.expectRevert(abi.encodePacked("INIT"));
        strategy.initialize(protocolAdmin, immutableParams, mutableParams);

        assertTrue(strategy.initialized());
    }

    function testUpdateMutableParams() external {
        BaseAmmStrategy.MutableParams memory params;

        vm.expectRevert(abi.encodePacked("FRB"));
        strategy.updateMutableParams(params);

        vm.startPrank(deployer);

        params.maxPriceSlippageX96 = Q96;
        vm.expectRevert(abi.encodePacked("LIMO"));
        strategy.updateMutableParams(params);
        params.maxPriceSlippageX96 = 0;

        params.maxTickDeviation = -1;
        vm.expectRevert(abi.encodePacked("LIMU"));
        strategy.updateMutableParams(params);
        params.maxTickDeviation = 0;

        params.minCapitalRatioDeviationX96 = Q96;
        vm.expectRevert(abi.encodePacked("LIMO"));
        strategy.updateMutableParams(params);
        params.minCapitalRatioDeviationX96 = 0;

        params.minSwapAmounts = new uint256[](1);
        vm.expectRevert(abi.encodePacked("INVL"));
        strategy.updateMutableParams(params);
        params.minSwapAmounts = new uint256[](2);

        params.maxCapitalRemainderRatioX96 = Q96;
        vm.expectRevert(abi.encodePacked("LIMO"));
        strategy.updateMutableParams(params);
        params.maxCapitalRemainderRatioX96 = 0;

        params.initialLiquidity = 0;
        vm.expectRevert(abi.encodePacked("VZ"));
        strategy.updateMutableParams(params);
        params.initialLiquidity = 1;

        params.securityParams = abi.encode("some invalid parameters");
        vm.expectRevert(bytes4(0xa86b6512));
        strategy.updateMutableParams(params);

        params.securityParams = abi.encode(
            VeloAdapter.SecurityParams({anomalyLookback: 3, anomalyOrder: 3, anomalyFactorD9: 2e9})
        );
        vm.expectRevert(bytes4(0xa86b6512));
        strategy.updateMutableParams(params);

        params.securityParams = abi.encode(
            VeloAdapter.SecurityParams({anomalyLookback: 3, anomalyOrder: 3, anomalyFactorD9: 1e9 - 1})
        );
        vm.expectRevert(bytes4(0xa86b6512));
        strategy.updateMutableParams(params);

        params.securityParams = abi.encode(
            VeloAdapter.SecurityParams({anomalyLookback: 3, anomalyOrder: 3, anomalyFactorD9: 1e10 + 1})
        );
        vm.expectRevert(bytes4(0xa86b6512));
        strategy.updateMutableParams(params);

        params = BaseAmmStrategy.MutableParams({
            securityParams: abi.encode(
                VeloAdapter.SecurityParams({anomalyLookback: 3, anomalyOrder: 2, anomalyFactorD9: 2e9})
            ),
            maxPriceSlippageX96: 0,
            maxTickDeviation: 0,
            minCapitalRatioDeviationX96: 0,
            minSwapAmounts: new uint256[](2),
            maxCapitalRemainderRatioX96: 0,
            initialLiquidity: 1
        });
        strategy.updateMutableParams(params);

        vm.stopPrank();
    }

    function testGetImmutableParams() external {
        BaseAmmStrategy.ImmutableParams memory immutableParams = strategy.getImmutableParams();

        assertEq(address(immutableParams.adapter), address(adapter));
        assertEq(address(immutableParams.pool), address(pool));
        assertEq(address(immutableParams.erc20Vault), address(erc20Vault));
        assertEq(immutableParams.ammVaults.length, 2);
        assertEq(address(immutableParams.ammVaults[0]), address(ammVault1));
        assertEq(address(immutableParams.ammVaults[1]), address(ammVault2));
    }

    function testGetMutableParams() external {
        vm.startPrank(deployer);
        BaseAmmStrategy.MutableParams memory params = BaseAmmStrategy.MutableParams({
            securityParams: abi.encode(
                VeloAdapter.SecurityParams({anomalyLookback: 3, anomalyOrder: 2, anomalyFactorD9: 2e9})
            ),
            maxPriceSlippageX96: 1,
            maxTickDeviation: 2,
            minCapitalRatioDeviationX96: 3,
            minSwapAmounts: new uint256[](2),
            maxCapitalRemainderRatioX96: 4,
            initialLiquidity: 5
        });
        strategy.updateMutableParams(params);

        vm.stopPrank();
        BaseAmmStrategy.MutableParams memory mutableParams = strategy.getMutableParams();
        assertEq(
            keccak256(mutableParams.securityParams),
            keccak256(
                abi.encode(VeloAdapter.SecurityParams({anomalyLookback: 3, anomalyOrder: 2, anomalyFactorD9: 2e9}))
            )
        );
        assertEq(mutableParams.maxPriceSlippageX96, 1);
        assertEq(mutableParams.maxTickDeviation, 2);
        assertEq(mutableParams.minCapitalRatioDeviationX96, 3);
        assertEq(mutableParams.maxCapitalRemainderRatioX96, 4);
        assertEq(mutableParams.initialLiquidity, 5);
        assertEq(mutableParams.minSwapAmounts.length, 2);
        assertEq(mutableParams.minSwapAmounts[0], 0);
        assertEq(mutableParams.minSwapAmounts[0], 0);
    }

    function testGetCurrentState() external {
        BaseAmmStrategy.Storage memory s;
        s.immutableParams = strategy.getImmutableParams();
        s.mutableParams = strategy.getMutableParams();
        BaseAmmStrategy.Position[] memory currentState = strategy.getCurrentState(s);

        assertEq(currentState.length, 2);
        assertTrue(currentState[0].capitalRatioX96 >= (Q96 * 99) / 100); // remaining ratio on erc20Vault
        assertEq(currentState[1].capitalRatioX96, 0);

        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        (uint256[] memory tvl, ) = rootVault.tvl();
        uint256 totalCapital = FullMath.mulDiv(tvl[0], priceX96, Q96) + tvl[1];

        (uint256[] memory ammTvl, ) = ammVault1.tvl();
        uint256 ammVault1Capital = FullMath.mulDiv(ammTvl[0], priceX96, Q96) + ammTvl[1];

        assertApproxEqAbs(
            FullMath.mulDiv(ammVault1Capital, Q96, totalCapital),
            currentState[0].capitalRatioX96,
            FullMath.mulDiv(Q96, 1, totalCapital) + 1
        );

        (uint256[] memory amm2Tvl, ) = ammVault2.tvl();
        assertEq(amm2Tvl[0], 0);
        assertEq(amm2Tvl[1], 0);
    }

    function testDepositCallback() external {
        uint256[] memory additionalAmounts = new uint256[](2);
        additionalAmounts[0] = 100 ether;
        additionalAmounts[1] = 200000 * 1e6;

        address[] memory tokens = ammVault1.vaultTokens();
        for (uint256 i = 0; i < 2; i++) {
            deal(tokens[i], address(erc20Vault), additionalAmounts[i]);
        }

        (uint256[] memory erc20TvlBefore, ) = erc20Vault.tvl();
        (uint256[] memory amm1TvlBefore, ) = ammVault1.tvl();

        strategy.depositCallback();

        (uint256[] memory erc20TvlAfter, ) = erc20Vault.tvl();
        (uint256[] memory amm1TvlAfter, ) = ammVault1.tvl();

        uint256[] memory pushedAmounts = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            pushedAmounts[i] = erc20TvlBefore[i] - erc20TvlAfter[i];
        }

        assertApproxEqAbs(amm1TvlBefore[0] + pushedAmounts[0], amm1TvlAfter[0], 1 wei);
        assertApproxEqAbs(amm1TvlBefore[1] + pushedAmounts[1], amm1TvlAfter[1], 1 wei);

        assertApproxEqAbs(
            FullMath.mulDiv(amm1TvlBefore[0], Q96, amm1TvlBefore[0] + amm1TvlBefore[1]),
            FullMath.mulDiv(pushedAmounts[0], Q96, pushedAmounts[0] + pushedAmounts[1]),
            FullMath.mulDiv(Q96, 2, amm1TvlBefore[0] + amm1TvlBefore[1])
        );
    }

    function calculateSwapData(BaseAmmStrategy.Position[] memory target)
        public
        view
        returns (BaseAmmStrategy.SwapData memory swapData)
    {
        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
        (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin) = baseAmmStrategyHelper
            .calculateSwapAmounts(sqrtPriceX96, target, rootVault, 3000);
        amountOutMin = (amountOutMin * 99) / 100;
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

        return
            BaseAmmStrategy.SwapData({
                router: address(swapRouter),
                data: data,
                tokenInIndex: tokenIn < tokenOut ? 0 : 1,
                amountIn: amountIn,
                amountOutMin: amountOutMin
            });
    }

    function _logState(BaseAmmStrategy.SwapData memory swapData) private view {
        BaseAmmStrategy.Storage memory s;
        s.immutableParams = strategy.getImmutableParams();
        s.mutableParams = strategy.getMutableParams();
        BaseAmmStrategy.Position[] memory currentState = strategy.getCurrentState(s);
        uint256 erc20CapitalRatio = Q96 - currentState[0].capitalRatioX96 - currentState[1].capitalRatioX96;
        address[] memory tokens = rootVault.vaultTokens();
        address tokenIn = tokens[swapData.tokenInIndex];
        console2.log(
            string(
                abi.encodePacked(
                    "token in: ",
                    IERC20Metadata(tokenIn).symbol(),
                    "; amount in: ",
                    vm.toString(swapData.amountIn / 10**IERC20Metadata(tokenIn).decimals()),
                    "; current erc20Capital ratio: ",
                    vm.toString((100 * erc20CapitalRatio) / Q96),
                    "%;"
                )
            )
        );
    }

    function testRebalance() external {
        BaseAmmStrategy.Storage memory s;
        s.immutableParams = strategy.getImmutableParams();
        s.mutableParams = strategy.getMutableParams();
        BaseAmmStrategy.Position[] memory state = strategy.getCurrentState(s);

        BaseAmmStrategy.SwapData memory emptySwapData;

        vm.expectRevert(abi.encodePacked("FRB"));
        strategy.rebalance(state, emptySwapData);

        vm.startPrank(deployer);
        for (uint256 i = 0; i < 4; i++) {
            (state[0], state[1]) = (state[1], state[0]);
            BaseAmmStrategy.SwapData memory swapData = calculateSwapData(state);
            strategy.rebalance(state, swapData);
            _logState(swapData);
        }

        console2.log("---------------");

        state[0].capitalRatioX96 = Q96 / 2;
        state[1].capitalRatioX96 = Q96 / 2;
        for (int24 i = 0; i < 4; i++) {
            state[0].tickLower = state[0].tickLower - TICK_SPACING;
            state[1].tickLower = state[0].tickLower + TICK_SPACING;
            state[1].tickUpper = state[0].tickUpper + TICK_SPACING;
            BaseAmmStrategy.SwapData memory swapData = calculateSwapData(state);
            strategy.rebalance(state, swapData);
            _logState(swapData);
        }

        console2.log("---------------");

        {
            (, int24 spotTick, , , , ) = pool.slot0();
            int24 remainder = spotTick % TICK_SPACING;
            if (remainder != 0) {
                spotTick -= TICK_SPACING + remainder;
            }

            for (int24 i = 0; i < 4; i++) {
                state[0].tickLower = spotTick - TICK_SPACING * i;
                state[0].tickUpper = spotTick + TICK_SPACING * (i + 1);
                state[0].capitalRatioX96 = (Q96 * uint24(i)) / 3;

                state[1].tickLower = spotTick - TICK_SPACING * i * 2;
                state[1].tickUpper = spotTick + TICK_SPACING * (i * 2 + 1);
                state[1].capitalRatioX96 = Q96 - state[0].capitalRatioX96;

                BaseAmmStrategy.SwapData memory swapData = calculateSwapData(state);
                strategy.rebalance(state, swapData);
                _logState(swapData);
            }
        }
        vm.stopPrank();
    }
}
