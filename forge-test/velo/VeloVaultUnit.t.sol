// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";

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

    address public protocolTreasury = address(bytes20(keccak256("protocol-treasury")));
    address public strategyTreasury = address(bytes20(keccak256("strategy-treasury")));
    address public deployerTreasury = address(bytes20(keccak256("deployer-treasury")));
    address public user = address(bytes20(keccak256("user")));
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
    IVeloVault public ammVault;

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
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));
        IVeloVaultGovernance(ammGovernance).createVault(tokens, deployer, TICK_SPACING);
        ammVault = IVeloVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        farm = new VeloFarm();

        ammGovernance.setStrategyParams(
            erc20VaultNft + 1,
            IVeloVaultGovernance.StrategyParams({farm: address(farm), gauge: address(gauge)})
        );

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
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
        uint8[] memory per = new uint8[](1);
        per[0] = 4;
        IProtocolGovernance(governance).stagePermissionGrants(address(swapRouter), per);
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
        minSwapAmounts[0] = 1e16;
        minSwapAmounts[1] = 1e7;

        IIntegrationVault[] memory ammVaults = new IIntegrationVault[](1);
        ammVaults[0] = ammVault;

        strategy.initialize(
            deployer,
            BaseAmmStrategy.ImmutableParams({
                erc20Vault: erc20Vault,
                ammVaults: ammVaults,
                adapter: adapter,
                pool: address(ammVault.pool())
            }),
            BaseAmmStrategy.MutableParams({
                securityParams: new bytes(0),
                maxPriceSlippageX96: (2 * Q96) / 100,
                maxTickDeviation: 50,
                minCapitalRatioDeviationX96: Q96 / 100,
                minSwapAmounts: minSwapAmounts,
                maxCapitalRemainderRatioX96: Q96,
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

    function initializeOperatorStrategy() public {
        operatorStrategy = new PulseOperatorStrategy();
        operatorStrategy.initialize(
            PulseOperatorStrategy.ImmutableParams({strategy: strategy, tickSpacing: pool.tickSpacing()}),
            PulseOperatorStrategy.MutableParams({
                positionWidth: 200,
                maxPositionWidth: 400,
                extensionFactorD: 1e9,
                neighborhoodFactorD: 1e8
            }),
            deployer
        );
        strategy.grantRole(strategy.ADMIN_DELEGATE_ROLE(), address(deployer));
        strategy.grantRole(strategy.OPERATOR(), address(operatorStrategy));

        deal(usdc, address(strategy), 1e15);
        deal(weth, address(strategy), 1e15);
    }

    function rebalance() public {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 expectedAmountOut;
        {
            (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
            BaseAmmStrategy.Position[] memory target = new BaseAmmStrategy.Position[](2);
            (BaseAmmStrategy.Position memory newPosition, ) = operatorStrategy.calculateExpectedPosition();
            target[0].tickLower = newPosition.tickLower;
            target[0].tickUpper = newPosition.tickUpper;
            target[0].capitalRatioX96 = Q96;
            (tokenIn, tokenOut, amountIn, expectedAmountOut) = baseAmmStrategyHelper.calculateSwapAmounts(
                sqrtPriceX96,
                target,
                rootVault,
                3000
            );
        }
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
        string memory spot;
        string memory pos;
        {
            (int24 tickLower, int24 tickUpper, ) = adapter.positionInfo(ammVault.tokenId());
            (uint160 sqrtPriceX96, int24 spotTick, , , , ) = pool.slot0();
            uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
            (uint256[] memory rv, ) = rootVault.tvl();
            (uint256[] memory uni, ) = ammVault.tvl();
            uint256 ratio = FullMath.mulDiv(
                100,
                FullMath.mulDiv(uni[0], priceX96, Q96) + uni[1],
                FullMath.mulDiv(rv[0], priceX96, Q96) + rv[1]
            );
            spot = string(
                abi.encodePacked(
                    vm.toString(tickLower <= spotTick && spotTick <= tickUpper),
                    " {",
                    vm.toString(spotTick),
                    "} ratio: ",
                    vm.toString(ratio),
                    "%"
                )
            );
            pos = string(abi.encodePacked("{", vm.toString(tickLower), ", ", vm.toString(tickUpper), "}"));
        }
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
        initializeOperatorStrategy();
        vm.stopPrank();
    }

    function fullInitialization() public {
        vm.startPrank(deployer);
        deposit(1);
        rebalance();

        depositWrapper.addNewStrategy(address(rootVault), address(farm), address(strategy), true);
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 10 ether;
        tokenAmounts[1] = 20000 * 1e6;
        address[] memory tokens = ammVault.vaultTokens();
        for (uint256 i = 0; i < tokenAmounts.length; i++) {
            deal(tokens[i], deployer, tokenAmounts[i]);
        }
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
        vm.stopPrank();
    }

    function getPositionInfo(uint256 tokenId)
        public
        view
        returns (
            uint128 liquidity,
            int24 tickLower,
            int24 tickUpper
        )
    {
        (, , , , , tickLower, tickUpper, liquidity, , , , ) = positionManager.positions(tokenId);
    }

    function calculateExpectedTvl(
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper
    ) public view returns (uint256 amount0, uint256 amount1) {
        uint160 sqrtLowerPriceX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtUpperPriceX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (uint160 sqrtSpotPriceX96, , , , , ) = pool.slot0();
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtSpotPriceX96,
            sqrtLowerPriceX96,
            sqrtUpperPriceX96,
            liquidity
        );
    }

    function testViewParametersAfterFinalInitialization() external {
        fullInitialization();

        require(address(ammVault.pool()) == address(pool));
        require(address(ammVault.helper()) == address(veloHelper));
        require(address(ammVault.positionManager()) == address(positionManager));
        require(ammVault.tokenId() != 0);
        require(address(ammVault.strategyParams().farm) == address(farm));
        require(address(ammVault.strategyParams().gauge) == address(gauge));
    }

    function testViewParametersBeforeFinalInitialization() external view {
        require(address(ammVault.pool()) == address(pool));
        require(address(ammVault.helper()) == address(veloHelper));
        require(address(ammVault.positionManager()) == address(positionManager));
        require(ammVault.tokenId() == 0);
        require(address(ammVault.strategyParams().farm) == address(farm));
        require(address(ammVault.strategyParams().gauge) == address(gauge));
    }

    function testSupportsInterface() external view {
        require(ammVault.supportsInterface(type(IVault).interfaceId));
        require(ammVault.supportsInterface(type(IVeloVault).interfaceId));
        require(!ammVault.supportsInterface(bytes4(uint32(1))));
    }

    function testTvl() external {
        {
            (uint256[] memory minTvl, uint256[] memory maxTvl) = ammVault.tvl();
            require(minTvl.length == 2 && maxTvl.length == 2);
            require(minTvl[0] == 0 && maxTvl[0] == 0);
            require(minTvl[1] == 0 && maxTvl[1] == 0);
        }

        fullInitialization();
        vm.startPrank(deployer);
        (, int24 initialTick, , , , ) = pool.slot0();
        (uint128 initialLiquidity, int24 initialTickLower, int24 initialTickUpper) = getPositionInfo(
            ammVault.tokenId()
        );

        require(initialTickLower <= initialTick && initialTick <= initialTickUpper);
        require(initialLiquidity > 0);

        {
            (uint256[] memory minTvl, uint256[] memory maxTvl) = ammVault.tvl();
            require(minTvl.length == 2 && maxTvl.length == 2);
            require(minTvl[0] > 0 && maxTvl[0] == minTvl[0]);
            require(minTvl[1] > 0 && maxTvl[1] == minTvl[1]);
            (uint128 liquidity, int24 tickLower, int24 tickUpper) = getPositionInfo(ammVault.tokenId());
            require(liquidity == initialLiquidity && tickLower == initialTickLower && tickUpper == initialTickUpper);
            (uint256 expectedAmount0, uint256 expectedAmount1) = calculateExpectedTvl(liquidity, tickLower, tickUpper);
            require(minTvl[0] == expectedAmount0 && minTvl[1] == expectedAmount1);
        }
        movePrice(initialTick - 1000);
        {
            (uint256[] memory minTvl, uint256[] memory maxTvl) = ammVault.tvl();
            require(minTvl.length == 2 && maxTvl.length == 2);
            require(minTvl[0] > 0 && maxTvl[0] == minTvl[0]);
            require(minTvl[1] == 0 && maxTvl[1] == minTvl[1]);
            (uint128 liquidity, int24 tickLower, int24 tickUpper) = getPositionInfo(ammVault.tokenId());
            require(liquidity == initialLiquidity && tickLower == initialTickLower && tickUpper == initialTickUpper);
            (uint256 expectedAmount0, uint256 expectedAmount1) = calculateExpectedTvl(liquidity, tickLower, tickUpper);
            require(minTvl[0] == expectedAmount0 && minTvl[1] == expectedAmount1);
        }
        movePrice(initialTick + 1000);
        {
            (uint256[] memory minTvl, uint256[] memory maxTvl) = ammVault.tvl();
            require(minTvl.length == 2 && maxTvl.length == 2);
            require(minTvl[0] == 0 && maxTvl[0] == minTvl[0]);
            require(minTvl[1] > 0 && maxTvl[1] == minTvl[1]);
            (uint128 liquidity, int24 tickLower, int24 tickUpper) = getPositionInfo(ammVault.tokenId());
            require(liquidity == initialLiquidity && tickLower == initialTickLower && tickUpper == initialTickUpper);
            (uint256 expectedAmount0, uint256 expectedAmount1) = calculateExpectedTvl(liquidity, tickLower, tickUpper);
            require(minTvl[0] == expectedAmount0 && minTvl[1] == expectedAmount1);
        }
        movePrice(initialTick);

        {
            (uint256[] memory minTvl, uint256[] memory maxTvl) = ammVault.tvl();
            require(minTvl.length == 2 && maxTvl.length == 2);
            require(minTvl[0] > 0 && maxTvl[0] == minTvl[0]);
            require(minTvl[1] > 0 && maxTvl[1] == minTvl[1]);
            (uint128 liquidity, int24 tickLower, int24 tickUpper) = getPositionInfo(ammVault.tokenId());
            require(liquidity == initialLiquidity && tickLower == initialTickLower && tickUpper == initialTickUpper);
            (uint256 expectedAmount0, uint256 expectedAmount1) = calculateExpectedTvl(liquidity, tickLower, tickUpper);
            require(minTvl[0] == expectedAmount0 && minTvl[1] == expectedAmount1);
        }
        vm.stopPrank();
    }

    function testInitilalize() external {
        address[] memory vaultTokens = ammVault.vaultTokens();
        int24 tickSpacing = ammVault.pool().tickSpacing();
        uint256 nft = ammVault.nft();
        vm.expectRevert(abi.encodePacked("INVL"));
        ammVault.initialize(0, new address[](0), 123);
        vm.expectRevert(abi.encodePacked("NF"));
        ammVault.initialize(0, vaultTokens, 123);
        vm.expectRevert(abi.encodePacked("INIT"));
        ammVault.initialize(0, vaultTokens, tickSpacing);
        vm.expectRevert(abi.encodePacked("INIT"));
        ammVault.initialize(nft, vaultTokens, tickSpacing);
        vm.expectRevert(abi.encodePacked("INIT"));
        ammVault.initialize(nft + 1, vaultTokens, tickSpacing);
        vm.expectRevert(abi.encodePacked("INIT"));
        ammVault.initialize(nft + 2, vaultTokens, tickSpacing);
    }

    function addRewardToGauge(uint256 amount) private {
        address voter = address(gauge.voter());
        address rewardToken = gauge.rewardToken();
        deal(rewardToken, voter, amount);
        vm.startPrank(voter);
        IERC20(rewardToken).safeIncreaseAllowance(address(gauge), amount);
        ICLGauge(gauge).notifyRewardAmount(amount);
        vm.stopPrank();
    }

    function _depositOnBehalf(address account, uint256[] memory tokenAmounts) private {
        vm.startPrank(account);
        address[] memory tokens = rootVault.vaultTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            deal(tokens[i], account, tokenAmounts[i]);
            IERC20(tokens[i]).safeApprove(address(depositWrapper), type(uint256).max);
        }
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
        vm.stopPrank();
    }

    function _testCollectRewards(uint256 ratioD2) private {
        require(ratioD2 > 0, "Invalid ratioD2 parameter");
        fullInitialization();

        {
            (uint256[] memory amounts, ) = rootVault.tvl();
            amounts[0] = (amounts[0] * (100 - ratioD2)) / ratioD2;
            amounts[1] = (amounts[1] * (100 - ratioD2)) / ratioD2;
            _depositOnBehalf(user, amounts);
        }

        uint256 amount = 10 ether;
        addRewardToGauge(amount);

        skip(7 days);
        ammVault.collectRewards();

        uint256 collectedRewardAmount = IERC20(gauge.rewardToken()).balanceOf(address(farm));
        assertApproxEqAbs(collectedRewardAmount, amount, 1 wei);

        uint256 expectedProtocolFee = FullMath.mulDiv(collectedRewardAmount, farm.getStorage().protocolFeeD9, 1e9);
        uint256 expectedUserRewards = collectedRewardAmount - expectedProtocolFee;

        uint256 deployerLp = farm.balanceOf(deployer);
        uint256 userLp = farm.balanceOf(user);

        vm.startPrank(deployer);
        assertEq(expectedUserRewards, farm.updateRewardAmounts());
        assertEq(expectedProtocolFee, IERC20(gauge.rewardToken()).balanceOf(protocolTreasury));

        uint256 expectedClaimedByDeployerAmounts = FullMath.mulDiv(
            deployerLp,
            expectedUserRewards,
            deployerLp + userLp
        );
        assertEq(expectedClaimedByDeployerAmounts, farm.claim(deployerTreasury));
        assertEq(expectedClaimedByDeployerAmounts, IERC20(gauge.rewardToken()).balanceOf(deployerTreasury));
        vm.stopPrank();

        vm.startPrank(user);
        uint256 expectedClaimedByUserAmounts = FullMath.mulDiv(userLp, expectedUserRewards, deployerLp + userLp);
        assertEq(expectedClaimedByUserAmounts, farm.claim(user));
        assertEq(expectedClaimedByUserAmounts, IERC20(gauge.rewardToken()).balanceOf(user));
        vm.stopPrank();
    }

    function testCollectRewardsQ05() external {
        _testCollectRewards(5);
    }

    function testCollectRewardsQ25() external {
        _testCollectRewards(25);
    }

    function testCollectRewardsQ50() external {
        _testCollectRewards(50);
    }

    function testCollectRewardsQ95() external {
        _testCollectRewards(95);
    }

    function _testPush(int24 q) private {
        fullInitialization();

        address[] memory tokens = ammVault.vaultTokens();
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2000 * 1e6;

        for (uint256 i = 0; i < 2; i++) {
            deal(tokens[i], address(erc20Vault), amounts[i]);
        }

        {
            (, int24 tickLower, int24 tickUpper) = getPositionInfo(ammVault.tokenId());
            vm.startPrank(deployer);
            movePrice(tickLower + ((tickUpper - tickLower) * q) / 100);
            vm.stopPrank();
        }

        (uint256[] memory erc20TvlBefore, ) = erc20Vault.tvl();
        (uint256[] memory ammTvlBefore, ) = ammVault.tvl();

        vm.startPrank(address(strategy));
        uint256[] memory actualPushedAmounts = erc20Vault.pull(address(ammVault), tokens, amounts, new bytes(0));
        vm.stopPrank();

        (uint256[] memory erc20TvlAfter, ) = erc20Vault.tvl();
        (uint256[] memory ammTvlAfter, ) = ammVault.tvl();

        assertApproxEqAbs(erc20TvlBefore[0] + ammTvlBefore[0], erc20TvlAfter[0] + ammTvlAfter[0], 1 wei);
        assertApproxEqAbs(erc20TvlBefore[1] + ammTvlBefore[1], erc20TvlAfter[1] + ammTvlAfter[1], 1 wei);

        assertApproxEqAbs(ammTvlBefore[0] + actualPushedAmounts[0], ammTvlAfter[0], 1 wei);
        assertApproxEqAbs(ammTvlBefore[1] + actualPushedAmounts[1], ammTvlAfter[1], 1 wei);

        if (q >= 100) {
            require(actualPushedAmounts[0] == 0 && actualPushedAmounts[1] > 0, "Invalid pushed amounts");
        } else if (q <= 0) {
            require(actualPushedAmounts[0] > 0 && actualPushedAmounts[1] == 0, "Invalid pushed amounts");
        } else {
            require(actualPushedAmounts[0] > 0 && actualPushedAmounts[1] > 0, "Invalid pushed amounts");
        }

        require(actualPushedAmounts[0] <= amounts[0] && actualPushedAmounts[1] <= amounts[1], "Invalid pushed amounts");

        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        uint256 expectedPushedRatioX96 = FullMath.mulDiv(
            ammTvlBefore[1],
            Q96,
            FullMath.mulDiv(ammTvlBefore[0], priceX96, Q96) + ammTvlBefore[1]
        );

        uint256 actualPushedRatioX96 = FullMath.mulDiv(
            actualPushedAmounts[1],
            Q96,
            FullMath.mulDiv(actualPushedAmounts[0], priceX96, Q96) + actualPushedAmounts[1]
        );

        assertApproxEqAbs(expectedPushedRatioX96, actualPushedRatioX96, Q96 / 1e8);
        if (q < 0) {
            assertApproxEqAbs(actualPushedRatioX96, 0, Q96 / 100);
        } else if (q <= 100) {
            assertApproxEqAbs(actualPushedRatioX96, (Q96 * uint24(q)) / 100, Q96 / 100);
        } else {
            assertApproxEqAbs(actualPushedRatioX96, Q96, Q96 / 100);
        }
    }

    function _testPull(int24 q) private {
        fullInitialization();

        address[] memory tokens = ammVault.vaultTokens();

        {
            (, int24 tickLower, int24 tickUpper) = getPositionInfo(ammVault.tokenId());
            vm.startPrank(deployer);
            movePrice(tickLower + ((tickUpper - tickLower) * q) / 100);
            vm.stopPrank();
        }

        (uint256[] memory amounts, ) = ammVault.tvl();
        amounts[0] /= 2;
        amounts[1] /= 2;

        (uint256[] memory erc20TvlBefore, ) = erc20Vault.tvl();
        (uint256[] memory ammTvlBefore, ) = ammVault.tvl();

        vm.startPrank(address(strategy));
        (uint256[] memory actualPulledAmounts, ) = erc20Vault.tvl();
        uint256[] memory pulledAmounts = ammVault.pull(address(erc20Vault), tokens, amounts, new bytes(0));
        {
            (uint256[] memory delta, ) = erc20Vault.tvl();
            for (uint256 i = 0; i < 2; i++) {
                actualPulledAmounts[i] = delta[i] - actualPulledAmounts[i];
                if (amounts[i] < actualPulledAmounts[i]) {
                    assertEq(pulledAmounts[i], amounts[i], "1");
                } else {
                    assertEq(pulledAmounts[i], actualPulledAmounts[i], "2");
                }
            }
        }

        vm.stopPrank();

        (uint256[] memory erc20TvlAfter, ) = erc20Vault.tvl();
        (uint256[] memory ammTvlAfter, ) = ammVault.tvl();

        assertApproxEqAbs(erc20TvlBefore[0] + ammTvlBefore[0], erc20TvlAfter[0] + ammTvlAfter[0], 1 wei);
        assertApproxEqAbs(erc20TvlBefore[1] + ammTvlBefore[1], erc20TvlAfter[1] + ammTvlAfter[1], 1 wei);

        assertApproxEqAbs(ammTvlBefore[0], actualPulledAmounts[0] + ammTvlAfter[0], 1 wei);
        assertApproxEqAbs(ammTvlBefore[1], actualPulledAmounts[1] + ammTvlAfter[1], 1 wei);

        if (q >= 100) {
            require(actualPulledAmounts[0] == 0 && actualPulledAmounts[1] > 0, "Invalid pushed amounts");
        } else if (q <= 0) {
            require(actualPulledAmounts[0] > 0 && actualPulledAmounts[1] == 0, "Invalid pushed amounts");
        } else {
            require(actualPulledAmounts[0] > 0 && actualPulledAmounts[1] > 0, "Invalid pushed amounts");
        }

        require(
            actualPulledAmounts[0] >= amounts[0] && actualPulledAmounts[1] >= amounts[1],
            "Invalid pushed amounts 2"
        );

        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        uint256 expectedPulledRatioX96 = FullMath.mulDiv(
            ammTvlBefore[1],
            Q96,
            FullMath.mulDiv(ammTvlBefore[0], priceX96, Q96) + ammTvlBefore[1]
        );

        uint256 actualPulledRatioX96 = FullMath.mulDiv(
            actualPulledAmounts[1],
            Q96,
            FullMath.mulDiv(actualPulledAmounts[0], priceX96, Q96) + actualPulledAmounts[1]
        );

        assertApproxEqAbs(expectedPulledRatioX96, actualPulledRatioX96, Q96 / 1e8);
        if (q < 0) {
            assertApproxEqAbs(actualPulledRatioX96, 0, Q96 / 100);
        } else if (q <= 100) {
            assertApproxEqAbs(actualPulledRatioX96, (Q96 * uint24(q)) / 100, Q96 / 100);
        } else {
            assertApproxEqAbs(actualPulledRatioX96, Q96, Q96 / 100);
        }
    }

    function testPushQ001_sub() external {
        _testPush(-1);
    }

    function testPushQ005() external {
        _testPush(5);
    }

    function testPushQ025() external {
        _testPush(25);
    }

    function testPushQ050() external {
        _testPush(50);
    }

    function testPushQ075() external {
        _testPush(75);
    }

    function testPushQ095() external {
        _testPush(95);
    }

    function testPushQ101() external {
        _testPush(101);
    }

    function testPullQ001_sub() external {
        _testPull(-1);
    }

    function testPullQ005() external {
        _testPull(5);
    }

    function testPullQ025() external {
        _testPull(25);
    }

    function testPullQ050() external {
        _testPull(50);
    }

    function testPullQ075() external {
        _testPull(75);
    }

    function testPullQ095() external {
        _testPull(95);
    }

    function testPullQ101() external {
        _testPull(101);
    }

    function _testPushOverflow(int24 q) private {
        fullInitialization();
        address[] memory tokens = ammVault.vaultTokens();
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2000 * 1e6;

        for (uint256 i = 0; i < 2; i++) {
            deal(tokens[i], address(erc20Vault), amounts[i]);
        }

        amounts[0] = 2 ether;
        amounts[1] = 4000 * 1e6;

        {
            (, int24 tickLower, int24 tickUpper) = getPositionInfo(ammVault.tokenId());
            vm.startPrank(deployer);
            movePrice(tickLower + ((tickUpper - tickLower) * q) / 100);
            vm.stopPrank();
        }

        (uint256[] memory erc20TvlBefore, ) = erc20Vault.tvl();
        (uint256[] memory ammTvlBefore, ) = ammVault.tvl();

        vm.startPrank(address(strategy));
        uint256[] memory actualPushedAmounts = erc20Vault.pull(address(ammVault), tokens, amounts, new bytes(0));
        vm.stopPrank();

        (uint256[] memory erc20TvlAfter, ) = erc20Vault.tvl();
        (uint256[] memory ammTvlAfter, ) = ammVault.tvl();

        assertApproxEqAbs(erc20TvlBefore[0] + ammTvlBefore[0], erc20TvlAfter[0] + ammTvlAfter[0], 1 wei);
        assertApproxEqAbs(erc20TvlBefore[1] + ammTvlBefore[1], erc20TvlAfter[1] + ammTvlAfter[1], 1 wei);

        assertApproxEqAbs(ammTvlBefore[0] + actualPushedAmounts[0], ammTvlAfter[0], 1 wei);
        assertApproxEqAbs(ammTvlBefore[1] + actualPushedAmounts[1], ammTvlAfter[1], 1 wei);

        if (q >= 100) {
            require(actualPushedAmounts[0] == 0 && actualPushedAmounts[1] > 0, "Invalid pushed amounts");
        } else if (q <= 0) {
            require(actualPushedAmounts[0] > 0 && actualPushedAmounts[1] == 0, "Invalid pushed amounts");
        } else {
            require(actualPushedAmounts[0] > 0 && actualPushedAmounts[1] > 0, "Invalid pushed amounts");
        }

        require(actualPushedAmounts[0] <= amounts[0] && actualPushedAmounts[1] <= amounts[1], "Invalid pushed amounts");

        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        uint256 expectedPushedRatioX96 = FullMath.mulDiv(
            ammTvlBefore[1],
            Q96,
            FullMath.mulDiv(ammTvlBefore[0], priceX96, Q96) + ammTvlBefore[1]
        );

        uint256 actualPushedRatioX96 = FullMath.mulDiv(
            actualPushedAmounts[1],
            Q96,
            FullMath.mulDiv(actualPushedAmounts[0], priceX96, Q96) + actualPushedAmounts[1]
        );

        assertApproxEqAbs(expectedPushedRatioX96, actualPushedRatioX96, Q96 / 1e8);
        if (q < 0) {
            assertApproxEqAbs(actualPushedRatioX96, 0, Q96 / 100);
        } else if (q <= 100) {
            assertApproxEqAbs(actualPushedRatioX96, (Q96 * uint24(q)) / 100, Q96 / 100);
        } else {
            assertApproxEqAbs(actualPushedRatioX96, Q96, Q96 / 100);
        }
    }

    function _testPullOverflow(int24 q) private {
        fullInitialization();

        address[] memory tokens = ammVault.vaultTokens();

        {
            (, int24 tickLower, int24 tickUpper) = getPositionInfo(ammVault.tokenId());
            vm.startPrank(deployer);
            movePrice(tickLower + ((tickUpper - tickLower) * q) / 100);
            vm.stopPrank();
        }

        (uint256[] memory amounts, ) = ammVault.tvl();
        amounts[0] *= 2;
        amounts[1] *= 2;

        (uint256[] memory erc20TvlBefore, ) = erc20Vault.tvl();
        (uint256[] memory ammTvlBefore, ) = ammVault.tvl();

        vm.startPrank(address(strategy));
        (uint256[] memory actualPulledAmounts, ) = erc20Vault.tvl();
        uint256[] memory pulledAmounts = ammVault.pull(address(erc20Vault), tokens, amounts, new bytes(0));
        {
            (uint256[] memory delta, ) = erc20Vault.tvl();
            for (uint256 i = 0; i < 2; i++) {
                actualPulledAmounts[i] = delta[i] - actualPulledAmounts[i];
                if (amounts[i] < actualPulledAmounts[i]) {
                    assertEq(pulledAmounts[i], amounts[i], "1");
                } else {
                    assertEq(pulledAmounts[i], actualPulledAmounts[i], "2");
                }
            }
        }

        vm.stopPrank();

        (uint256[] memory erc20TvlAfter, ) = erc20Vault.tvl();
        (uint256[] memory ammTvlAfter, ) = ammVault.tvl();

        assertApproxEqAbs(erc20TvlBefore[0] + ammTvlBefore[0], erc20TvlAfter[0] + ammTvlAfter[0], 1 wei);
        assertApproxEqAbs(erc20TvlBefore[1] + ammTvlBefore[1], erc20TvlAfter[1] + ammTvlAfter[1], 1 wei);

        assertApproxEqAbs(ammTvlBefore[0], actualPulledAmounts[0] + ammTvlAfter[0], 1 wei);
        assertApproxEqAbs(ammTvlBefore[1], actualPulledAmounts[1] + ammTvlAfter[1], 1 wei);

        if (q >= 100) {
            require(actualPulledAmounts[0] == 0 && actualPulledAmounts[1] > 0, "Invalid pushed amounts");
        } else if (q <= 0) {
            require(actualPulledAmounts[0] > 0 && actualPulledAmounts[1] == 0, "Invalid pushed amounts");
        } else {
            require(actualPulledAmounts[0] > 0 && actualPulledAmounts[1] > 0, "Invalid pushed amounts");
        }

        require(
            actualPulledAmounts[0] <= amounts[0] && actualPulledAmounts[1] <= amounts[1],
            "Invalid pushed amounts 2"
        );

        (uint160 sqrtPriceX96, , , , , ) = pool.slot0();
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        uint256 expectedPulledRatioX96 = FullMath.mulDiv(
            ammTvlBefore[1],
            Q96,
            FullMath.mulDiv(ammTvlBefore[0], priceX96, Q96) + ammTvlBefore[1]
        );

        uint256 actualPulledRatioX96 = FullMath.mulDiv(
            actualPulledAmounts[1],
            Q96,
            FullMath.mulDiv(actualPulledAmounts[0], priceX96, Q96) + actualPulledAmounts[1]
        );

        assertApproxEqAbs(expectedPulledRatioX96, actualPulledRatioX96, Q96 / 1e8);
        if (q < 0) {
            assertApproxEqAbs(actualPulledRatioX96, 0, Q96 / 100);
        } else if (q <= 100) {
            assertApproxEqAbs(actualPulledRatioX96, (Q96 * uint24(q)) / 100, Q96 / 100);
        } else {
            assertApproxEqAbs(actualPulledRatioX96, Q96, Q96 / 100);
        }
    }

    function testPushOverflowQ001_sub() external {
        _testPushOverflow(-1);
    }

    function testPushOverflowQ005() external {
        _testPushOverflow(5);
    }

    function testPushOverflowQ025() external {
        _testPushOverflow(25);
    }

    function testPushOverflowQ050() external {
        _testPushOverflow(50);
    }

    function testPushOverflowQ075() external {
        _testPushOverflow(75);
    }

    function testPushOverflowQ095() external {
        _testPushOverflow(95);
    }

    function testPushOverflowQ101() external {
        _testPushOverflow(101);
    }

    function testPullOverflowQ001_sub() external {
        _testPullOverflow(-1);
    }

    function testPullOverflowQ005() external {
        _testPullOverflow(5);
    }

    function testPullOverflowQ025() external {
        _testPullOverflow(25);
    }

    function testPullOverflowQ050() external {
        _testPullOverflow(50);
    }

    function testPullOverflowQ075() external {
        _testPullOverflow(75);
    }

    function testPullOverflowQ095() external {
        _testPullOverflow(95);
    }

    function testPullOverflowQ101() external {
        _testPullOverflow(101);
    }
}
