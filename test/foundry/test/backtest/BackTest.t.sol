// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/ProtocolGovernance.sol";
import "../../src/VaultRegistry.sol";
import "../../src/ERC20RootVaultHelper.sol";
import "../../src/MockOracle.sol";

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

    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address lRoot = 0x13c7bCc2126d6892eEFd489Ad215A1a09F36AA9f;

    address sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;

    address deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    LStrategy lStrategy = LStrategy(0xeF39C188E2Bc8EB45dAF49A3fE2f72Bf32050892);
    PulseStrategyV2 pulseStrategy = PulseStrategyV2(0xFDF8B88D77a9B65646e0D9Cd5880E3677B94Af01);
    address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address lRebalancer = 0xbd619B7E8ba7defe20a4C7EBD3C6DcE6Eb26a5Ea;

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
           // console2.log(uint24(currentPoolTick));
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

      //  console.log("S");
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

         //   console2.log("REBALANCE");

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



    function test() public {

        IUniswapV3Pool pool = lStrategy.lowerVault().pool();

        setUpOracle();
        setUpPrice();

        int24 tick = getTick(pool);

        for (uint256 i = 1; i <= 150; ++i) {

            int24 newTick = tick + int24(uint24(i));

            makeDesiredPoolPrice(pool, newTick);
            setUpPrice();

            if (lastRebalanceTick + 50 < newTick) {
                rebalanceLStrategy(newTick);
            }

            (uint256[] memory minTvl, ) = IERC20RootVault(lRoot).tvl();
        }


    }

}