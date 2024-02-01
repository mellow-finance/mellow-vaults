// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// import "forge-std/src/Test.sol";
// import "forge-std/src/Vm.sol";
// import "forge-std/src/console2.sol";

// import "@openzeppelin/contracts/utils/Strings.sol";

// import "../../src/strategies/BaseAmmStrategy.sol";

// import "../../src/test/MockRouter.sol";

// import "../../src/utils/VeloDepositWrapper.sol";
// import "../../src/utils/VeloHelper.sol";
// import "../../src/utils/BaseAmmStrategyHelper.sol";
// import "../../src/utils/VeloDeployFactory.sol";

// import "../../src/vaults/ERC20Vault.sol";
// import "../../src/vaults/ERC20VaultGovernance.sol";

// import "../../src/vaults/ERC20RootVault.sol";
// import "../../src/vaults/ERC20RootVaultGovernance.sol";

// import "../../src/vaults/VeloVault.sol";
// import "../../src/vaults/VeloVaultGovernance.sol";

// import "../../src/adapters/VeloAdapter.sol";

// import "../../src/strategies/PulseOperatorStrategy.sol";

// import {SwapRouter} from "./contracts/periphery/SwapRouter.sol";

// contract Integration is Test {
//     using SafeERC20 for IERC20;

//     uint256 public constant Q96 = 2**96;
//     int24 public constant TICK_SPACING = 200;

//     address public protocolTreasury = address(bytes20(keccak256("treasury-1")));
//     address public strategyTreasury = address(bytes20(keccak256("treasury-2")));
//     address public farmTreasury = address(bytes20(keccak256("treasury-3")));
//     address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
//     address public protocolAdmin = 0xAe259ed3699d1416840033ABAf92F9dD4534b2DC;

//     uint256 public protocolFeeD9 = 1e8; // 10%

//     address public weth = 0x4200000000000000000000000000000000000006;
//     address public usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
//     address public velo = 0x9560e827aF36c94D2Ac33a39bCE1Fe78631088Db;

//     address public governance = 0x6CeFdD08d633c4A92380E8F6217238bE2bd1d841;
//     address public registry = 0x5cC7Cb6fD996dD646cF613ac94E9E0D2436a083A;
//     address public allowAllValidator = 0x0f4A979597E16ec87d2344fD78c2cec53f37D263;
//     address public mellowOracle = 0xA9FC72eE105D43C885E48Ab18148D308A55d04c7;

//     address public erc20VaultGovernance = 0xb55ef318B5F73414c91201Af4F467b6c5fE73Ece;
//     address public erc20RootVaultGovernance = 0x65a440a89824AB464d7c94B184eF494c1457258D;
//     address public protocolGovernance = 0x6CeFdD08d633c4A92380E8F6217238bE2bd1d841;
//     address public vaultRegistry = 0x5cC7Cb6fD996dD646cF613ac94E9E0D2436a083A;

//     ICLPool public pool = ICLPool(0xC358c95b146E9597339b376063A2cB657AFf84eb);
//     ICLGauge public gauge = ICLGauge(0x5f090Fc694aa42569aB61397E4c996E808f0BBf2);

//     INonfungiblePositionManager public positionManager =
//         INonfungiblePositionManager(0xd557d3b47D159EB3f9B48c0f1B4a6e67e82e8B3f);
//     SwapRouter public swapRouter = new SwapRouter(positionManager.factory(), weth);
//     ICLGaugeFactory public gaugeFactory = ICLGaugeFactory(positionManager.gaugeFactory());
//     ICLFactory public factory = ICLFactory(positionManager.factory());

//     IVeloVaultGovernance public ammGovernance;
//     VeloHelper public veloHelper = new VeloHelper(positionManager);
//     VeloAdapter public veloAdapter = new VeloAdapter(positionManager);
//     BaseAmmStrategyHelper public baseStrategyHelper = new BaseAmmStrategyHelper();
//     VeloDepositWrapper public depositWrapper;

//     VeloDeployFactory public deployFactory;
//     VeloDeployFactory.VaultInfo public vaultInfo;

//     function deployGovernance() public {
//         VeloVault singleton = new VeloVault(positionManager, veloHelper);
//         ammGovernance = new VeloVaultGovernance(
//             IVaultGovernance.InternalParams({
//                 singleton: singleton,
//                 registry: IVaultRegistry(registry),
//                 protocolGovernance: IProtocolGovernance(governance)
//             })
//         );

//         vm.stopPrank();
//         vm.startPrank(protocolAdmin);

//         uint8[] memory permissions = new uint8[](1);
//         permissions[0] = 0;
//         IProtocolGovernance(governance).stagePermissionGrants(address(ammGovernance), permissions);
//         permissions[0] = 4;
//         IProtocolGovernance(governance).stagePermissionGrants(address(swapRouter), permissions);
//         permissions[0] = 1;
//         IProtocolGovernance(governance).stagePermissionGrants(address(deployFactory), permissions);

//         IProtocolGovernance(governance).stageValidator(address(swapRouter), allowAllValidator);

//         skip(24 * 3600);
//         IProtocolGovernance(governance).commitPermissionGrants(address(ammGovernance));
//         IProtocolGovernance(governance).commitPermissionGrants(address(deployFactory));
//         IProtocolGovernance(governance).commitPermissionGrants(address(swapRouter));
//         IProtocolGovernance(governance).commitValidator(address(swapRouter));

//         vm.stopPrank();
//         vm.startPrank(deployer);
//     }

//     function deposit(uint256 coef) public {
//         uint256[] memory tokenAmounts = vaultInfo.rootVault.pullExistentials();
//         address[] memory tokens = vaultInfo.rootVault.vaultTokens();
//         for (uint256 i = 0; i < tokens.length; i++) {
//             tokenAmounts[i] *= 10 * coef;
//             deal(tokens[i], deployer, tokenAmounts[i]);
//             IERC20(tokens[i]).safeIncreaseAllowance(address(depositWrapper), tokenAmounts[i]);
//         }
//         depositWrapper.deposit(vaultInfo.rootVault, tokenAmounts, 0, new bytes(0));
//     }

//     function rebalance() public {
//         address tokenIn;
//         address tokenOut;
//         uint256 amountIn;
//         uint256 expectedAmountOut;
//         {
//             (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
//             BaseAmmStrategy.Position[] memory target = new BaseAmmStrategy.Position[](2);
//             (BaseAmmStrategy.Position memory newPosition, ) = PulseOperatorStrategy(vaultInfo.operatorStrategy)
//                 .calculateExpectedPosition();
//             target[0].tickLower = newPosition.tickLower;
//             target[0].tickUpper = newPosition.tickUpper;
//             target[0].capitalRatioX96 = Q96;
//             (tokenIn, tokenOut, amountIn, expectedAmountOut) = baseStrategyHelper.calculateSwapAmounts(
//                 sqrtPriceX96,
//                 target,
//                 vaultInfo.rootVault,
//                 3000
//             );
//         }
//         uint256 amountOutMin = (expectedAmountOut * 99) / 100;
//         bytes memory data = abi.encodeWithSelector(
//             ISwapRouter.exactInputSingle.selector,
//             ISwapRouter.ExactInputSingleParams({
//                 tokenIn: tokenIn,
//                 tokenOut: tokenOut,
//                 tickSpacing: TICK_SPACING,
//                 amountIn: amountIn,
//                 deadline: type(uint256).max,
//                 recipient: address(vaultInfo.erc20Vault),
//                 amountOutMinimum: amountOutMin,
//                 sqrtPriceLimitX96: 0
//             })
//         );

//         PulseOperatorStrategy(vaultInfo.operatorStrategy).rebalance(
//             BaseAmmStrategy.SwapData({
//                 router: address(swapRouter),
//                 data: data,
//                 tokenInIndex: tokenIn < tokenOut ? 0 : 1,
//                 amountIn: amountIn,
//                 amountOutMin: amountOutMin
//             })
//         );

//         string memory spot;
//         {
//             (int24 tickLower, int24 tickUpper, ) = veloAdapter.positionInfo(
//                 IVeloVault(address(vaultInfo.veloVaults[0])).tokenId()
//             );

//             (uint160 sqrtPriceX96, int24 spotTick, , , , ) = pool.slot0();
//             uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

//             (uint256[] memory rootVaultTvl, ) = vaultInfo.rootVault.tvl();
//             (uint256[] memory ammVaultTvl, ) = vaultInfo.veloVaults[0].tvl();
//             uint256 ratioD2 = FullMath.mulDiv(
//                 100,
//                 FullMath.mulDiv(ammVaultTvl[0], priceX96, Q96) + ammVaultTvl[1],
//                 FullMath.mulDiv(rootVaultTvl[0], priceX96, Q96) + rootVaultTvl[1]
//             );

//             bool flag = tickLower <= spotTick && spotTick <= tickUpper;
//             assertTrue(flag);

//             spot = string(
//                 abi.encodePacked(
//                     "erc20Vault capital ratio: ",
//                     vm.toString(ratioD2),
//                     "%; range: [",
//                     vm.toString(tickLower),
//                     ", ",
//                     vm.toString(tickUpper),
//                     "] spot tick: ",
//                     vm.toString(spotTick)
//                 )
//             );
//         }

//         if (tokenIn == address(0)) {
//             console2.log("nothing to rebalace;", spot);
//         } else {
//             console2.log(
//                 string(
//                     abi.encodePacked(
//                         "token in: ",
//                         IERC20Metadata(tokenIn).symbol(),
//                         "; amount in: ",
//                         vm.toString(amountIn / 10**IERC20Metadata(tokenIn).decimals()),
//                         "; ",
//                         spot
//                     )
//                 )
//             );
//         }
//     }

//     function _swapAmount(uint256 amountIn, uint256 tokenInIndex) private {
//         if (amountIn == 0) revert("Insufficient amount for swap");
//         address[] memory tokens = new address[](2);
//         tokens[0] = weth;
//         tokens[1] = usdc;
//         address tokenIn = tokens[tokenInIndex];
//         address tokenOut = tokens[tokenInIndex ^ 1];
//         deal(tokenIn, deployer, amountIn);
//         IERC20(tokenIn).safeIncreaseAllowance(address(swapRouter), amountIn);
//         ISwapRouter(address(swapRouter)).exactInputSingle(
//             ISwapRouter.ExactInputSingleParams({
//                 tokenIn: tokenIn,
//                 tokenOut: tokenOut,
//                 tickSpacing: TICK_SPACING,
//                 recipient: deployer,
//                 amountIn: amountIn,
//                 amountOutMinimum: 0,
//                 sqrtPriceLimitX96: 0,
//                 deadline: type(uint256).max
//             })
//         );
//         skip(24 * 3600);
//     }

//     function movePrice(int24 targetTick) public {
//         int24 spotTick;
//         (, spotTick, , , , ) = pool.slot0();
//         uint256 usdcAmount = IERC20(usdc).balanceOf(address(pool));
//         uint256 wethAmount = IERC20(weth).balanceOf(address(pool));
//         if (spotTick < targetTick) {
//             while (spotTick < targetTick) {
//                 _swapAmount(usdcAmount, 1);
//                 (, spotTick, , , , ) = pool.slot0();
//             }
//         } else {
//             while (spotTick > targetTick) {
//                 _swapAmount(wethAmount, 0);
//                 (, spotTick, , , , ) = pool.slot0();
//             }
//         }

//         while (spotTick != targetTick) {
//             if (spotTick < targetTick) {
//                 while (spotTick < targetTick) {
//                     _swapAmount(usdcAmount, 1);
//                     (, spotTick, , , , ) = pool.slot0();
//                 }
//                 usdcAmount >>= 1;
//             } else {
//                 while (spotTick > targetTick) {
//                     _swapAmount(wethAmount, 0);
//                     (, spotTick, , , , ) = pool.slot0();
//                 }
//                 wethAmount >>= 1;
//             }
//         }
//     }

//     function addLiquidity(
//         int24 tickLower,
//         int24 tickUpper,
//         uint128 liquidity
//     ) public {
//         (uint160 sqrtRatioX96, , , , , ) = pool.slot0();
//         (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
//             sqrtRatioX96,
//             TickMath.getSqrtRatioAtTick(tickLower),
//             TickMath.getSqrtRatioAtTick(tickUpper),
//             liquidity
//         );
//         deal(weth, address(veloAdapter), amount0 * 2);
//         deal(usdc, address(veloAdapter), amount1 * 2);
//         veloAdapter.mint(address(pool), tickLower, tickUpper, liquidity, address(veloAdapter));
//     }

//     function normalizePool() public {
//         pool.increaseObservationCardinalityNext(2);
//         {
//             int24 lowerTick = -800000;
//             int24 upperTick = 800000;
//             addLiquidity(lowerTick, upperTick, 2500 ether);
//         }

//         (, int24 targetTick, , , , , ) = IUniswapV3Pool(0x85149247691df622eaF1a8Bd0CaFd40BC45154a9).slot0();

//         _swapAmount(2621439999999999988840005632, 0);
//         movePrice(targetTick);

//         targetTick -= targetTick % TICK_SPACING;

//         {
//             (uint160 sqrtRatioX96, , , , , ) = pool.slot0();
//             uint256 priceX96 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, Q96);
//             uint256 usdcAmount = 5e12;
//             uint256 wethAmount = FullMath.mulDiv(usdcAmount, Q96, priceX96);

//             for (int24 i = 1; i <= 20; i++) {
//                 int24 lowerTick = targetTick - i * TICK_SPACING;
//                 int24 upperTick = targetTick + i * TICK_SPACING;
//                 uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
//                     sqrtRatioX96,
//                     TickMath.getSqrtRatioAtTick(lowerTick),
//                     TickMath.getSqrtRatioAtTick(upperTick),
//                     wethAmount,
//                     usdcAmount
//                 );
//                 addLiquidity(lowerTick, upperTick, liquidity);
//             }
//         }

//         skip(3 * 24 * 3600);
//     }

//     function _testWidth(int24 maxWidth) private {
//         vm.startPrank(deployer);

//         normalizePool();
//         deployFactory = new VeloDeployFactory(
//             deployer,
//             positionManager,
//             ISwapRouter(address(swapRouter)),
//             factory,
//             gaugeFactory
//         );

//         depositWrapper = new VeloDepositWrapper(deployer);
//         depositWrapper.grantRole(depositWrapper.ADMIN_ROLE(), address(deployFactory));

//         deployGovernance();

//         deployFactory.updateInternalParams(
//             VeloDeployFactory.InternalParams({
//                 addresses: VeloDeployFactory.MellowProtocolAddresses({
//                     erc20VaultGovernance: 0xb55ef318B5F73414c91201Af4F467b6c5fE73Ece,
//                     erc20RootVaultGovernance: 0x65a440a89824AB464d7c94B184eF494c1457258D,
//                     veloVaultGovernance: address(ammGovernance),
//                     protocolGovernance: 0x6CeFdD08d633c4A92380E8F6217238bE2bd1d841,
//                     vaultRegistry: 0x5cC7Cb6fD996dD646cF613ac94E9E0D2436a083A,
//                     protocolTreasury: protocolTreasury,
//                     strategyTreasury: strategyTreasury,
//                     farmTreasury: farmTreasury,
//                     veloAdapter: address(veloAdapter),
//                     veloHelper: address(veloHelper),
//                     depositWrapper: address(depositWrapper),
//                     baseStrategySingleton: address(new BaseAmmStrategy()),
//                     operatorStrategySingleton: address(new PulseOperatorStrategy()),
//                     farmSingleton: address(new VeloFarm()),
//                     baseStrategyHelper: address(baseStrategyHelper),
//                     operator: deployer
//                 }),
//                 protocolFeeD9: 1e8,
//                 positionsCount: 2,
//                 liquidityCoefficient: 365 // possible number of mints
//             })
//         );

//         uint256[] memory minSwapAmounts = new uint256[](2);
//         minSwapAmounts[0] = 1e9;
//         minSwapAmounts[1] = 1e3;
//         deployFactory.updateBaseDefaultMutableParams(
//             TICK_SPACING,
//             BaseAmmStrategy.MutableParams({
//                 securityParams: new bytes(0),
//                 maxPriceSlippageX96: (2 * Q96) / 100,
//                 maxTickDeviation: 50,
//                 minCapitalRatioDeviationX96: Q96 / 100,
//                 minSwapAmounts: minSwapAmounts,
//                 maxCapitalRemainderRatioX96: Q96 / 20,
//                 initialLiquidity: 1e9
//             })
//         );

//         deployFactory.updateOperatorDefaultMutableParams(
//             TICK_SPACING,
//             PulseOperatorStrategy.MutableParams({
//                 positionWidth: 200,
//                 maxPositionWidth: maxWidth,
//                 extensionFactorD: 1e9,
//                 neighborhoodFactorD: 1e8
//             })
//         );

//         deal(weth, deployer, 1 ether);
//         deal(usdc, deployer, 1e6 * 2200);

//         IERC20(weth).safeApprove(address(deployFactory), type(uint256).max);
//         IERC20(usdc).safeApprove(address(deployFactory), type(uint256).max);

//         vaultInfo = deployFactory.createStrategy(weth, usdc, TICK_SPACING);

//         deposit(1e7);

//         uint24 steps = 5;
//         int24 width = 200;
//         (, int24 tick, , , , ) = pool.slot0();

//         for (uint256 j = 0; j < steps; j++) {
//             deposit(1e7);
//             for (uint24 i = 0; i < steps; i++) {
//                 movePrice(tick - int24(i) * width - width / 2);
//                 rebalance();
//             }
//             for (uint24 i = 0; i < steps; i++) {
//                 movePrice(tick + int24(i) * width + width / 2);
//                 rebalance();
//             }
//         }
//         vm.stopPrank();
//     }

//     function testNarrow() external {
//         _testWidth(200);
//     }

//     function testNormal() external {
//         _testWidth(800);
//     }

//     function testWide() external {
//         _testWidth(4200);
//     }
// }
