// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/utils/UniV3Helper.sol";
import "../../src/MockOracle.sol";
import "../../src/MockRouter.sol";

import "../../src/interfaces/external/univ3/ISwapRouter.sol";

import "../../src/vaults/UniV3VaultGovernance.sol";
import "../../src/strategies/PulseStrategy.sol";

import "../../src/interfaces/vaults/IERC20RootVaultGovernance.sol";
import "../../src/interfaces/vaults/IERC20VaultGovernance.sol";
import "../../src/interfaces/vaults/IUniV3VaultGovernance.sol";

import "../../src/interfaces/vaults/IERC20RootVault.sol";
import "../../src/interfaces/vaults/IERC20Vault.sol";
import "../../src/interfaces/vaults/IUniV3Vault.sol";

import "../../src/vaults/UniV3Vault.sol";

contract PulseStrategyTest is Test {

    IERC20RootVault public rootVault;
    IERC20Vault erc20Vault;
    IUniV3Vault uniV3Vault;

    PulseStrategy pulseStrategy;

    uint256 nftStart;
    address sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public uniV3Governance = 0x9c319DC47cA6c8c5e130d5aEF5B8a40Cce9e877e;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;
    address public positionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    function firstDeposit() public {
        
        deal(usdc, deployer, 10**4);
        deal(weth, deployer, 10**10);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10**4;
        amounts[1] = 10**10;

        IERC20(usdc).approve(address(rootVault), type(uint256).max);
        IERC20(weth).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function deposit(uint256 amount) public {

        if (rootVault.totalSupply() == 0) {
            firstDeposit();
        }

        deal(usdc, deployer, amount * 10**6);
        deal(weth, deployer, amount * 10**15);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount * 10**6;
        amounts[1] = amount * 10**15;

        IERC20(usdc).approve(address(rootVault), type(uint256).max);
        IERC20(weth).approve(address(rootVault), type(uint256).max);

        bytes memory depositInfo;

        rootVault.deposit(amounts, 0, depositInfo);
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(pulseStrategy), nfts, deployer);
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

/*
    uint256 A0;
    uint256 A1;

    function preparePush(address vault) public {

        int24 tickLower = 0;
        int24 tickUpper = 4000;

        IPool pool = kyberVault.pool();

        (int24 tickLowerQ, ) = pool.initializedTicks(tickLower); 
        (int24 tickUpperQ, ) = pool.initializedTicks(tickUpper);

        int24[2] memory Qticks;
        Qticks[0] = tickLowerQ;
        Qticks[1] = tickUpperQ; 
        
        IERC20(bob).approve(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8, type(uint256).max);
        IERC20(stmatic).approve(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8, type(uint256).max);
        deal(bob, deployer, 10**9);
        deal(stmatic, deployer, 10**9);

        (uint256 nft, , uint256 A0_, uint256 A1_) = IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8).mint(
            IBasePositionManager.MintParams({
                token0: stmatic,
                token1: bob,
                fee: 1000,
                tickLower: 0,
                tickUpper: 4000,
                ticksPrevious: Qticks,
                amount0Desired: 10**9,
                amount1Desired: 10**9,
                amount0Min: 0,
                amount1Min: 0,
                recipient: operator,
                deadline: type(uint256).max
            })
        );

        A0 = A0_;
        A1 = A1_;

        IVaultRegistry(registry).approve(operator, IVault(vault).nft());

        vm.stopPrank();
        vm.startPrank(operator);

        IBasePositionManager(0x2B1c7b41f6A8F2b2bc45C3233a5d5FB3cD6dC9A8).safeTransferFrom(operator, vault, nft);

        vm.stopPrank();
        vm.startPrank(deployer);
    }
*/

    MockRouter mockRouter;
    MockOracle mockOracle;

    function kek() public payable returns (uint256 startNft) {

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = usdc;
        tokens[1] = weth;

        UniV3Helper uniHelper = new UniV3Helper(INonfungiblePositionManager(positionManager));

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, deployer);

            IUniV3VaultGovernance uniVaultGovernance = IUniV3VaultGovernance(uniV3Governance);
            uniVaultGovernance.createVault(tokens, deployer, 500, address(uniHelper));

            IUniV3VaultGovernance.DelayedStrategyParams memory params = IUniV3VaultGovernance.DelayedStrategyParams({
                safetyIndicesSet: 2
            });

            uniVaultGovernance.stageDelayedStrategyParams(erc20VaultNft + 1, params);
            uniVaultGovernance.commitDelayedStrategyParams(erc20VaultNft + 1);

        }

        mockOracle = new MockOracle();

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));
        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        pulseStrategy = new PulseStrategy(INonfungiblePositionManager(positionManager));

        mockRouter = new MockRouter(tokens, mockOracle);

        {
            uint8[] memory grant = new uint8[](2);
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

        address W = 0xa8a78538Fc6D44951d6e957192a9772AfB02dd2f;

        vm.stopPrank();
        vm.startPrank(admin);

        IProtocolGovernance(governance).stageValidator(address(mockRouter), W);
        vm.warp(block.timestamp + 86400);
        IProtocolGovernance(governance).commitValidator(address(mockRouter));

        vm.stopPrank();
        vm.startPrank(deployer);

        PulseStrategy.ImmutableParams memory sParams = PulseStrategy.ImmutableParams({
            erc20Vault: erc20Vault,
            uniV3Vault: uniV3Vault,
            tokens: tokens
        });

        uint256[] memory AA = new uint256[](2);
        AA[0] = 10**6;
        AA[1] = 10**15;

        PulseStrategy.MutableParams memory smParams = PulseStrategy.MutableParams({
            forceRebalanceWidth: false,
            priceImpactD6: 0,
            defaultIntervalWidth: 3000,
            maxPositionLengthInTicks: 8000,
            maxDeviationForVaultPool: 50,
            timespanForAverageTick: 900,
            router: address(mockRouter),
            neighborhoodFactorD: 10 ** 8,
            extensionFactorD: 2 * 10 ** 8,
            swapSlippageD: 10 ** 7,
            swappingAmountsCoefficientD: 10 ** 7,
            minSwapAmounts: AA
        });

        PulseStrategy.DesiredAmounts memory smdParams = PulseStrategy.DesiredAmounts({
            amount0Desired: 10 ** 4,
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

        pulseStrategy.initialize(sParams, deployer);
        pulseStrategy.updateMutableParams(smParams);
        pulseStrategy.updateDesiredAmounts(smdParams);

        deal(usdc, address(pulseStrategy), 10**12);
        deal(weth, address(pulseStrategy), 10**12);

        deal(weth, address(mockRouter), 10**22);
        deal(usdc, address(mockRouter), 10**13);
    }

    function updateRouter() public {
        IUniswapV3Pool pool = uniV3Vault.pool();
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 P = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 2**96);
        mockOracle.updatePrice(P);
    }

    function getTick() public returns (int24 tick) {
        IUniswapV3Pool pool = uniV3Vault.pool();
        (, tick, , , , , ) = pool.slot0();
    }

    function swapTokens(
        address recepient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public {

        ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        
        deal(tokenIn, deployer, amountIn);
        IERC20(tokenIn).approve(address(router), type(uint256).max);

        ISwapRouter(router).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 500,
                recipient: recepient,
                deadline: type(uint256).max,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function makeDesiredPoolPrice(int24 tick) public {
        IUniswapV3Pool pool = uniV3Vault.pool();
        uint256 startTry = 10**22;

        uint256 needIncrease = 0;

        while (true) {
            (, int24 currentPoolTick, , , , , ) = pool.slot0();
            if (currentPoolTick == tick) {
                break;
            }

            if (currentPoolTick < tick) {
                if (needIncrease == 0) {
                    needIncrease = 1;
                    startTry = startTry / 2;
                }
                swapTokens(deployer, weth, usdc, startTry);
            } else {
                if (needIncrease == 1) {
                    needIncrease = 0;
                    startTry = startTry / 2;
                }
                swapTokens(deployer, usdc, weth, startTry / 10**9);
            }
        }
    }

    function calcTvl() public returns (uint256) {
        (uint256[] memory tvl, ) = rootVault.tvl();

        IUniswapV3Pool pool = uniV3Vault.pool();
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        uint256 P = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 2**96);

        return tvl[1] + FullMath.mulDiv(tvl[0], P, 2**96);
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

    function testSetup() public {
        firstDeposit();
        deposit(1000);
    }

    function testSimpleRebalance() public {
        firstDeposit();
        deposit(1000);

        updateRouter();

        bytes memory data = bytes("");

        uint256 oldTvl = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl = calcTvl();

        console2.log(oldTvl);
        console2.log(newTvl);

        require(newTvl * 1000 > oldTvl * 999);

        require(uniV3Vault.uniV3Nft() != 0);

        int24 tick = getTick();

        (, , , , , int24 lowerTick, int24 upperTick, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        int24 middleTick = (lowerTick + upperTick) / 2;
        require(middleTick < tick + 100 && tick < middleTick + 100);
        
        (uint256[] memory minTvl, ) = erc20Vault.tvl();
        require(minTvl[0] < 10**5);
        require(minTvl[1] < 10**14); // rebalance drained erc20vault to new uni position
        require(IERC20(weth).balanceOf(address(uniV3Vault)) == 0);
        require(IERC20(usdc).balanceOf(address(uniV3Vault)) == 0);
    }

    function testNoRebalanceNeeded() public {
        firstDeposit();
        deposit(10000);

        updateRouter();

        bytes memory data = bytes("");

        uint256 oldTvl = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl = calcTvl();
        require(newTvl * 1000 > oldTvl * 999);

        (, , , , , int24 lowerTick, int24 upperTick, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        makeDesiredPoolPrice(lowerTick + 500);

        vm.warp(block.timestamp + 3600);

        updateRouter();

        uint256 oldNft = uniV3Vault.uniV3Nft();

        deal(usdc, deployer, 10**8);
        IERC20(usdc).transfer(address(erc20Vault), 10**8);

        uint256 oldTvl2 = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl2 = calcTvl();

        uint256 newNft = uniV3Vault.uniV3Nft();

        require(oldNft == newNft);

        (, , , , , int24 lowerTick2, int24 upperTick2, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        uint24 oldLength = uint24(upperTick - lowerTick);
        uint24 newLength = uint24(upperTick2 - lowerTick2);

        console2.log(oldLength);
        console2.log(newLength);

        require(oldLength == 3000);
        require(newLength == 3000);

        (uint256[] memory minTvl, ) = erc20Vault.tvl();
        require(minTvl[0] < 10**5);
        require(minTvl[1] < 10**14); // rebalance drained erc20vault to new uni position
        require(IERC20(weth).balanceOf(address(uniV3Vault)) == 0);
        require(IERC20(usdc).balanceOf(address(uniV3Vault)) == 0);

        require(lowerTick2 == lowerTick);
        require(upperTick2 == upperTick);
    }

    function testNoRebalanceNeededAfterRebalance() public {
        firstDeposit();
        deposit(10000);

        updateRouter();

        bytes memory data = bytes("");

        uint256 oldTvl = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl = calcTvl();
        require(newTvl * 1000 > oldTvl * 999);

        (, , , , , int24 lowerTick, int24 upperTick, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        makeDesiredPoolPrice(lowerTick);

        vm.warp(block.timestamp + 3600);

        updateRouter();

        uint256 oldTvl2 = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl2 = calcTvl();
        require(newTvl2 * 1000 > oldTvl2 * 999);

        deal(usdc, deployer, 10**8);
        IERC20(usdc).transfer(address(erc20Vault), 10**8);
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);

        (, , , , , int24 lowerTick2, int24 upperTick2, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        uint24 oldLength = uint24(upperTick - lowerTick);
        uint24 newLength = uint24(upperTick2 - lowerTick2);

        console2.log(oldLength);
        console2.log(newLength);

        require(newLength > oldLength);
    }

    function testRebalanceAfterPriceMove1() public {
        firstDeposit();
        deposit(10000);

        updateRouter();

        bytes memory data = bytes("");

        uint256 oldTvl = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl = calcTvl();
        require(newTvl * 1000 > oldTvl * 999);

        (, , , , , int24 lowerTick, int24 upperTick, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        makeDesiredPoolPrice(lowerTick + 250);

        vm.warp(block.timestamp + 3600);

        updateRouter();

        uint256 oldNft = uniV3Vault.uniV3Nft();

        uint256 oldTvl2 = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl2 = calcTvl();
        require(newTvl2 * 1000 > oldTvl2 * 999);

        uint256 newNft = uniV3Vault.uniV3Nft();

        require(oldNft != newNft);

        (, , , , , int24 lowerTick2, int24 upperTick2, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        uint24 oldLength = uint24(upperTick - lowerTick);
        uint24 newLength = uint24(upperTick2 - lowerTick2);

        console2.log(oldLength);
        console2.log(newLength);

        require(oldLength == 3000);
        require(newLength == 4180);

        (uint256[] memory minTvl, ) = erc20Vault.tvl();
        require(minTvl[0] < 10**5);
        require(minTvl[1] < 10**14); // rebalance drained erc20vault to new uni position
        require(IERC20(weth).balanceOf(address(uniV3Vault)) == 0);
        require(IERC20(usdc).balanceOf(address(uniV3Vault)) == 0);

        require(lowerTick2 == lowerTick - 590);
        require(upperTick2 == upperTick + 590);
    }

    function testRebalanceAfterPriceMovesToTheBorder() public {
        firstDeposit();
        deposit(10000);

        updateRouter();

        bytes memory data = bytes("");

        uint256 oldTvl = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl = calcTvl();
        require(newTvl * 1000 > oldTvl * 999);

        (, , , , , int24 lowerTick, int24 upperTick, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        makeDesiredPoolPrice(lowerTick);

        vm.warp(block.timestamp + 3600);

        updateRouter();

        uint256 oldNft = uniV3Vault.uniV3Nft();

        uint256 oldTvl2 = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl2 = calcTvl();
        require(newTvl2 * 1000 > oldTvl2 * 999);

        uint256 newNft = uniV3Vault.uniV3Nft();

        require(oldNft != newNft);

        (, , , , , int24 lowerTick2, int24 upperTick2, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        uint24 oldLength = uint24(upperTick - lowerTick);
        uint24 newLength = uint24(upperTick2 - lowerTick2);

        console2.log(oldLength);
        console2.log(newLength);

        require(oldLength == 3000);
        require(newLength == 5000);

        (uint256[] memory minTvl, ) = erc20Vault.tvl();
        require(minTvl[0] < 10**5);
        require(minTvl[1] < 10**14); // rebalance drained erc20vault to new uni position
        require(IERC20(weth).balanceOf(address(uniV3Vault)) == 0);
        require(IERC20(usdc).balanceOf(address(uniV3Vault)) == 0);

        require(lowerTick2 == lowerTick - 1000);
        require(upperTick2 == upperTick + 1000);
    }

    function testRebalanceAfterPriceMovesOutOfTheBorder() public {
        firstDeposit();
        deposit(10000);

        updateRouter();

        bytes memory data = bytes("");

        uint256 oldTvl = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl = calcTvl();
        require(newTvl * 1000 > oldTvl * 999);

        (, , , , , int24 lowerTick, int24 upperTick, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        makeDesiredPoolPrice(upperTick + 500);

        vm.warp(block.timestamp + 3600);

        updateRouter();

        uint256 oldNft = uniV3Vault.uniV3Nft();

        uint256 oldTvl2 = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl2 = calcTvl();
        require(newTvl2 * 1000 > oldTvl2 * 999);

        uint256 newNft = uniV3Vault.uniV3Nft();

        require(oldNft != newNft);

        (, , , , , int24 lowerTick2, int24 upperTick2, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        uint24 oldLength = uint24(upperTick - lowerTick);
        uint24 newLength = uint24(upperTick2 - lowerTick2);

        console2.log(oldLength);
        console2.log(newLength);

        require(oldLength == 3000);
        require(newLength == 6680);

        (uint256[] memory minTvl, ) = erc20Vault.tvl();
        require(minTvl[0] < 10**5);
        require(minTvl[1] < 10**14); // rebalance drained erc20vault to new uni position
        require(IERC20(weth).balanceOf(address(uniV3Vault)) == 0);
        require(IERC20(usdc).balanceOf(address(uniV3Vault)) == 0);

        require(lowerTick2 == lowerTick - 1840);
        require(upperTick2 == upperTick + 1840);
    }

    function testRebalanceForced() public {
        firstDeposit();
        deposit(10000);

        updateRouter();

        bytes memory data = bytes("");
        
        {
            uint256 oldTvl = calcTvl();
            pulseStrategy.rebalance(block.timestamp + 1, data, 0);
            uint256 newTvl = calcTvl();
            require(newTvl * 1000 > oldTvl * 999);
        }

        (, , , , , int24 lowerTick, int24 upperTick, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        makeDesiredPoolPrice(lowerTick);

        vm.warp(block.timestamp + 3600);

        updateRouter();

        {

            uint256[] memory AA = new uint256[](2);
            AA[0] = 10**6;
            AA[1] = 10**15;

            PulseStrategy.MutableParams memory smParams = PulseStrategy.MutableParams({
                forceRebalanceWidth: true,
                priceImpactD6: 0,
                defaultIntervalWidth: 3000,
                maxPositionLengthInTicks: 8000,
                maxDeviationForVaultPool: 50,
                timespanForAverageTick: 900,
                router: address(mockRouter),
                neighborhoodFactorD: 10 ** 8,
                extensionFactorD: 2 * 10 ** 8,
                swapSlippageD: 10 ** 7,
                swappingAmountsCoefficientD: 10 ** 7,
                minSwapAmounts: AA
            });

            pulseStrategy.updateMutableParams(smParams);

        }

        uint256 oldNft = uniV3Vault.uniV3Nft();

        {
            uint256 oldTvl2 = calcTvl();
            pulseStrategy.rebalance(block.timestamp + 1, data, 0);
            uint256 newTvl2 = calcTvl();
            require(newTvl2 * 1000 > oldTvl2 * 999);
        }

        uint256 newNft = uniV3Vault.uniV3Nft();

        require(oldNft != newNft);

        (, , , , , int24 lowerTick2, int24 upperTick2, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        {

            uint24 oldLength = uint24(upperTick - lowerTick);
            uint24 newLength = uint24(upperTick2 - lowerTick2);

            console2.log(oldLength);
            console2.log(newLength);

            require(oldLength == 3000);
            require(newLength == 3000);

        }

        (uint256[] memory minTvl, ) = erc20Vault.tvl();
        require(minTvl[0] < 10**5);
        require(minTvl[1] < 10**14); // rebalance drained erc20vault to new uni position
        console2.log(IERC20(weth).balanceOf(address(uniV3Vault)));
        console2.log(IERC20(usdc).balanceOf(address(uniV3Vault)));
        require(IERC20(weth).balanceOf(address(uniV3Vault)) == 0);
        require(IERC20(usdc).balanceOf(address(uniV3Vault)) == 0);

        makeDesiredPoolPrice(lowerTick2);

        vm.warp(block.timestamp + 3600);

        updateRouter();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);

        (, , , , , int24 lowerTick3, int24 upperTick3, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        uint24 newestLength = uint24(upperTick3 - lowerTick3);

        require(newestLength > 3000);
    }

    function testRebalanceAfterPriceMovesVeryOutOfTheBorder() public {
        firstDeposit();
        deposit(10000);

        updateRouter();

        bytes memory data = bytes("");

        uint256 oldTvl = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl = calcTvl();
        require(newTvl * 1000 > oldTvl * 999);

        (, , , , , int24 lowerTick, int24 upperTick, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        makeDesiredPoolPrice(upperTick + 3000);

        vm.warp(block.timestamp + 3600);

        updateRouter();

        uint256 oldNft = uniV3Vault.uniV3Nft();

        uint256 oldTvl2 = calcTvl();
        pulseStrategy.rebalance(block.timestamp + 1, data, 0);
        uint256 newTvl2 = calcTvl();
        require(newTvl2 * 1000 > oldTvl2 * 999);

        uint256 newNft = uniV3Vault.uniV3Nft();

        require(oldNft != newNft);

        (, , , , , int24 lowerTick2, int24 upperTick2, , , , , ) = pulseStrategy.positionManager().positions(uniV3Vault.uniV3Nft());

        uint24 oldLength = uint24(upperTick - lowerTick);
        uint24 newLength = uint24(upperTick2 - lowerTick2);

        console2.log(oldLength);
        console2.log(newLength);

        require(oldLength == 3000);
        require(newLength == 3000);

        (uint256[] memory minTvl, ) = erc20Vault.tvl();
        require(minTvl[0] < 10**5);
        require(minTvl[1] < 10**14); // rebalance drained erc20vault to new uni position
        require(IERC20(weth).balanceOf(address(uniV3Vault)) == 0);
        require(IERC20(usdc).balanceOf(address(uniV3Vault)) == 0);
    }
}