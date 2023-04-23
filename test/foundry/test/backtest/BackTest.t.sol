// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/VaultRegistry.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/MockOracle.sol";
import "../../src/MockRouter.t.sol";

import "../../src/utils/UniV3Helper.sol";
import "../../src/utils/LStrategyHelper.sol";
import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20RootVault.sol";

import "../../src/vaults/GearboxVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";
import "../../src/vaults/UniV3VaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/strategies/LStrategy.sol";
import "../../src/strategies/PulseStrategyV2.sol";

contract BackTest is Test {

    using stdStorage for StdStorage;

    uint256 D6 = 10**6;
    uint256 Q96 = 2**96;

    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address helper = 0x612716674b54b757c808Df58B0D10EB079C809A5;

    address lRoot = 0x13c7bCc2126d6892eEFd489Ad215A1a09F36AA9f;
    address pRoot = 0x5Fd7eA4e9F96BBBab73D934618a75746Fd88e460;

    address sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;

    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    LStrategy lStrategy = LStrategy(0xeF39C188E2Bc8EB45dAF49A3fE2f72Bf32050892);
    PulseStrategyV2 pulseStrategy = PulseStrategyV2(0xFDF8B88D77a9B65646e0D9Cd5880E3677B94Af01);
    address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address lRebalancer = 0xbd619B7E8ba7defe20a4C7EBD3C6DcE6Eb26a5Ea;
    address governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;

    MockRouter inchRouter;

    function setUp() external {
        vm.startPrank(deployer);
    }

    function getTick(IUniswapV3Pool pool) public returns (int24 tick) {
        (, tick, , , , , ) = pool.slot0();
    }

    function add(address token, address account, uint256 amount) public {
        uint256 balance = IERC20(token).balanceOf(account);
        deal(token, account, balance + amount);
    }

    function sub(address token, address account, uint256 amount) public {
        uint256 balance = IERC20(token).balanceOf(account);
        deal(token, account, balance - amount);
    }

    function swapTokens(
        address sender,
        address recipient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public {

        add(tokenIn, sender, amountIn);

        IERC20(tokenIn).approve(router, type(uint256).max);

        ISwapRouter(router).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 500,
                recipient: recipient,
                deadline: type(uint256).max,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

    }

    function makeDesiredPoolPrice(IUniswapV3Pool pool, int24 tick) public {

        uint256 startTry = 3 * 10**18;

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
                swapTokens(deployer, deployer, weth, wsteth, startTry);
            } else {
                if (needIncrease == 1) {
                    needIncrease = 0;
                    startTry = startTry / 2;
                }
                swapTokens(deployer, deployer, wsteth, weth, startTry);
            }
        }

    }

    int24 lastRebalanceTick = 0;

    function rebalanceLStrategy(int24 tick) public {

        vm.stopPrank();
        vm.startPrank(lRebalancer);

        while (true) {
            uint256[] memory EA = new uint256[](2);

            (uint256[] memory A, uint256[] memory B, , ,) = lStrategy.rebalanceUniV3Vaults(EA, EA, type(uint256).max);
            (uint256[] memory C, ,) = lStrategy.rebalanceERC20UniV3Vaults(EA, EA, type(uint256).max);

            LStrategy.PreOrder memory preOrder = lStrategy.postPreOrder(0);

            uint256 amountIn = preOrder.amountIn;

            if (A[0] == 0 && B[0] == 0 && A[1] == 0 && B[1] == 0 && C[0] == 0 && C[1] == 0 && amountIn == 0) {
                break;
            }

            lastRebalanceTick = tick;

            (, uint32 maxSlippageD, , , , ) = lStrategy.tradingParams();
            uint256 amountOut = FullMath.mulDiv(preOrder.minAmountOut, 10**9, 10**9 - maxSlippageD);

            sub(preOrder.tokenIn, address(lStrategy.erc20Vault()), amountIn);
            add(preOrder.tokenOut, address(lStrategy.erc20Vault()), amountOut);

            vm.warp(block.timestamp + 3600);
        }

        vm.stopPrank();
        vm.startPrank(deployer);

    }

    MockOracle m;

    function setUpOracle() public {
        vm.stopPrank();
        vm.startPrank(sAdmin);

        m = new MockOracle();

        (, uint32 b, uint32 c, uint256 d, uint256 e, uint256 f) = lStrategy.tradingParams();

        lStrategy.updateTradingParams(LStrategy.TradingParams({
            oracle: m,
            maxSlippageD: b,
            orderDeadline: c,
            oracleSafetyMask: d,
            maxFee0: e,
            maxFee1: d
        }));

        vm.stopPrank();
        vm.startPrank(deployer);
    }

    function getPrice() public returns (uint256) {
        IUniswapV3Pool pool = lStrategy.lowerVault().pool();
        (uint256 p, , , , , ,) = pool.slot0();

        return FullMath.mulDiv(p, p, 2**96);
    }

    function setUpPrice() public {
        m.updatePrice(getPrice());
    }

    function getMutableParams() public returns (PulseStrategyV2.MutableParams memory) {
        (int24 priceImpactD6, int24 defaultIntervalWidth, int24 maxPositionLengthInTicks, int24 maxDeviationForVaultPool, uint32 timespanForAverageTick, uint256 neighborhoodFactorD, uint256 extensionFactorD, uint256 swapSlippageD, uint256 swappingAmountsCoefficientD) = pulseStrategy.mutableParams();
        uint256[] memory minSwapAmounts = new uint256[](2);

        minSwapAmounts[0] = 10**15;
        minSwapAmounts[1] = 10**15;
        
        return PulseStrategyV2.MutableParams({
            priceImpactD6: priceImpactD6,
            defaultIntervalWidth: defaultIntervalWidth,
            maxPositionLengthInTicks: maxPositionLengthInTicks,
            maxDeviationForVaultPool: maxDeviationForVaultPool,
            timespanForAverageTick: timespanForAverageTick,
            neighborhoodFactorD: neighborhoodFactorD,
            extensionFactorD: extensionFactorD,
            swapSlippageD: swapSlippageD,
            swappingAmountsCoefficientD: swappingAmountsCoefficientD,
            minSwapAmounts: minSwapAmounts
        });
    }

    function getImmutableParams() public returns (PulseStrategyV2.ImmutableParams memory) {
        (IERC20Vault erc20Vault, IUniV3Vault uniV3Vault, address router) = pulseStrategy.immutableParams();

        address[] memory tokens = new address[](2);

        tokens[0] = wsteth;
        tokens[1] = weth;
        
        return PulseStrategyV2.ImmutableParams({
            erc20Vault: erc20Vault,
            uniV3Vault: uniV3Vault, 
            router: router,
            tokens: tokens
        });
    }

    function calculateTvl(PulseStrategyV2.ImmutableParams memory immutableParams, uint160 pp, uint256 nft) public view returns (uint256[] memory tvl) {
        IERC20Vault erc20Vault = immutableParams.erc20Vault;
        
        (tvl, ) = erc20Vault.tvl();

        uint256[] memory uniTvl = UniV3Helper(helper).calculateTvlBySqrtPriceX96(nft, pp);
        tvl[0] += uniTvl[0];
        tvl[1] += uniTvl[1];
    }

    function pulseTvl() public returns (uint256[] memory tvl) {

        IUniswapV3Pool pool = lStrategy.lowerVault().pool();
        (uint160 pp, , , , , ,) = pool.slot0();

        (, IUniV3Vault uniV3Vault, ) = pulseStrategy.immutableParams();

        return calculateTvl(getImmutableParams(), pp, uniV3Vault.uniV3Nft());
    }

    function calculateAmountsForSwap(
        PulseStrategyV2.ImmutableParams memory immutableParams,
        PulseStrategyV2.MutableParams memory mutableParams,
        uint256 priceX96,
        uint256 targetRatioOfToken1X96,
        uint160 pp,
        uint256 nft
    ) public view returns (uint256 tokenInIndex, uint256 amountIn) {

        uint256 targetRatioOfToken0X96 = Q96 - targetRatioOfToken1X96;

        (uint256[] memory currentAmounts) = calculateTvl(immutableParams, pp, nft);

        uint256 currentRatioOfToken1X96 = FullMath.mulDiv(
            currentAmounts[1],
            Q96,
            currentAmounts[1] + FullMath.mulDiv(currentAmounts[0], priceX96, Q96)
        );

        uint256 feesX96 = FullMath.mulDiv(Q96, uint256(int256(mutableParams.priceImpactD6)), D6);

        if (currentRatioOfToken1X96 > targetRatioOfToken1X96) {
            tokenInIndex = 1;
            // (dx * y0 - dy * x0 * p) / (1 - dy * fee)
            uint256 invertedPriceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(currentAmounts[1], targetRatioOfToken0X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken1X96, currentAmounts[0], invertedPriceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken1X96, feesX96, Q96)
            );
        } else {
            // (dy * x0 - dx * y0 / p) / (1 - dx * fee)
            tokenInIndex = 0;
            amountIn = FullMath.mulDiv(
                FullMath.mulDiv(currentAmounts[0], targetRatioOfToken1X96, Q96) -
                    FullMath.mulDiv(targetRatioOfToken0X96, currentAmounts[1], priceX96),
                Q96,
                Q96 - FullMath.mulDiv(targetRatioOfToken0X96, feesX96, Q96)
            );
        }
        if (amountIn > currentAmounts[tokenInIndex]) {
            amountIn = currentAmounts[tokenInIndex];
        }
    }

    function rebalancePulseStrategy(IUniswapV3Pool pool, int24 tick) public returns (bool) {

        vm.stopPrank();
        vm.startPrank(sAdmin);

        (, IUniV3Vault uniV3Vault, ) = pulseStrategy.immutableParams();

        (uint160 pp, , , , , ,) = pool.slot0();

        (, , , , , int24 lowerTick, int24 upperTick, , , , , ) = pulseStrategy.positionManager().positions(
            uniV3Vault.uniV3Nft()
        );

        int24 currentNeighborhood;

        {

            (, , , , , uint256 neiFactorD , , , ) = pulseStrategy.mutableParams();

            currentNeighborhood = int24(
                uint24(FullMath.mulDiv(uint24(upperTick - lowerTick), neiFactorD, 10**9))
            );

        }

        if (tick > upperTick - currentNeighborhood) {

            (PulseStrategyV2.Interval memory interval, ) = pulseStrategy.calculateNewPosition(getMutableParams(), tick, pool, uniV3Vault.uniV3Nft());

            uint256 pr = FullMath.mulDiv(pp, pp, 2**96);
            
            uint256 targetRatio = pulseStrategy.calculateTargetRatioOfToken1(interval, pp, pr);
            (uint256 tokenInIndex, uint256 amountIn) = calculateAmountsForSwap(getImmutableParams(), getMutableParams(), pr, targetRatio, pp, uniV3Vault.uniV3Nft());

            bytes memory data;
            if (tokenInIndex == 0) {
                data = abi.encodePacked(MockRouter.swap.selector, abi.encode(wsteth, weth, amountIn, FullMath.mulDiv(amountIn, pr, Q96)));
            }
            
            else {
                data = abi.encodePacked(MockRouter.swap.selector, abi.encode(weth, wsteth, amountIn, FullMath.mulDiv(amountIn, Q96, pr)));
            }

            pulseStrategy.rebalance(type(uint256).max, data, 0);

            vm.stopPrank();
            vm.startPrank(deployer);

            return true;
        }

        vm.stopPrank();
        vm.startPrank(deployer);

        return false;
    }

    function setNewRouter() public {

        vm.stopPrank();
        inchRouter = new MockRouter();
        vm.startPrank(deployer);

        vm.store(address(pulseStrategy), bytes32(uint256(5)), bytes32(uint256(uint160(address(inchRouter)))));

        (, , address rou) = pulseStrategy.immutableParams();

        require(rou == address(inchRouter));

        address validator = 0xa8a78538Fc6D44951d6e957192a9772AfB02dd2f;

        vm.stopPrank();
        vm.startPrank(admin);

        ProtocolGovernance(governance).stageValidator(address(inchRouter), validator);
        vm.warp(block.timestamp + 86400);
        ProtocolGovernance(governance).commitValidator(address(inchRouter));

        vm.stopPrank();
        vm.startPrank(deployer);

    }

    function test() public {

        setNewRouter();

        IUniswapV3Pool pool = lStrategy.lowerVault().pool();

        setUpOracle();
        setUpPrice();

        int24 tick = getTick(pool);

        for (uint256 i = 1; i <= 500; ++i) {

            int24 newTick = tick + int24(uint24(i));

            console2.log(uint24(newTick));

            makeDesiredPoolPrice(pool, newTick);
            setUpPrice();

            if (lastRebalanceTick + 50 < newTick) {
                rebalanceLStrategy(newTick);
            }

            bool was = rebalancePulseStrategy(pool, newTick);

            (uint256[] memory minTvl, ) = IERC20RootVault(lRoot).tvl();
            uint256[] memory minTvl2 = pulseTvl();

            console2.log(IERC20RootVault(lRoot).totalSupply());
            console2.log(minTvl2[1]);
            console2.log(minTvl2[0]);

            console2.log(IERC20RootVault(lRoot).totalSupply());
            console2.log(minTvl[1]);
            console2.log(minTvl[0]);

            console2.log(1488);


        }


    }

}