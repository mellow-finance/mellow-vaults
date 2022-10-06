// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../lib/forge-std/src/console2.sol";
import "../lib/forge-std/src/Vm.sol";
import "../lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../test/helpers/IVaultRegistry.sol";
import "../test/helpers/IUniV3VaultGovernance.sol";
import "../test/helpers/IYearnVaultGovernance.sol";
import "../test/helpers/IERC20VaultGovernance.sol";
import "../test/helpers/IERC20RootVaultGovernance.sol";
import "../test/helpers/utils/UniV3Helper.sol";

import "../src/HStrategy.sol";
import "../src/MockOracle.sol";
import "./HFeedContract.sol";

contract HBacktest is Test {

    HStrategy strategy;
    address public admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;
    address public uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniswapV3PositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public uniGovernance = 0x8306bec30063f00F5ffd6976f09F6b10E77B27F2;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public yearnGovernance = 0xD7286673FD2d56EF9b324783835e2594674629D5;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public deployer = address(this);

    UniV3Helper helperTmp = new UniV3Helper();
    address public uniHelper = address(helperTmp);
    address public hHelper = 0xAdf65e524ecbc6Dc3077047A977349f65Ab4E88E;

    uint256 startPriceD9 = 1469 * 10**9; 
    uint256 currentPriceD9 = 1469 * 10**9;
    uint256 minEthPrice = 1469 * 10**9;
    uint256 maxEthPrice = 1469 * 10**9;
    address public rootVault;

    IERC20Vault erc20Vault;
    IUniV3Vault uniV3Vault;
    IYearnVault yearnVault;

    uint256 usdcIntervalVolume = 10 * 10**12; // 10M USD every 3 hours estimation
    uint256 necessarySwapsAmount; // resets after each 3h
    uint256 initialLiquidityAmount; // adjusting
    uint256 yearnAPY = 2 * 10**7; // 2% APY estimation

    HFeed feed = new HFeed();

    uint256 startTvlA = 100000 * 10**6;
    uint256 startTvlB = 68 * 10**18;

    function tvl() public returns (uint256 tvlA, uint256 tvlB) {

        (uint256[] memory tA, ) = erc20Vault.tvl();
        (uint256[] memory tB, ) = uniV3Vault.tvl();
        (uint256[] memory tC, ) = yearnVault.tvl();

        tvlA += tA[0] + tB[0] + tC[0];
        tvlB += tA[1] + tB[1] + tC[1];

    }

    function ethToUsd(uint256 amount, uint256 price) public returns (uint256) {
        return FullMath.mulDiv(amount, price, 10**21);
    }

    function getUSDPNTvl() public returns (uint256) {
        (uint256 tvlA, uint256 tvlB) = tvl();
        return FullMath.mulDiv(ethToUsd(tvlB, currentPriceD9) + tvlA, ethToUsd(startTvlB, startPriceD9) + startTvlA, ethToUsd(startTvlB, currentPriceD9) + startTvlA);
    }

    function getUSDTvl() public returns (uint256) {
        (uint256 tvlA, uint256 tvlB) = tvl();
        return ethToUsd(tvlB, currentPriceD9) + tvlA;
    }
    
    function rebalance() public {
        uint256[] memory emptyUArray = new uint256[](2);
        int256[] memory emptyArray = new int256[](2);

        HStrategy.RebalanceTokenAmounts memory defaultAmounts = HStrategy.RebalanceTokenAmounts({
            pulledToUniV3Vault: emptyUArray,
            pulledFromUniV3Vault: emptyUArray,
            swappedAmounts: emptyArray,
            burnedAmounts: emptyUArray,
            deadline: type(uint256).max
        });

        vm.prank(admin);
        strategy.rebalance(defaultAmounts, "");
    }

    MockOracle mockOracle;

    function setOraclePrice() public {
        IUniswapV3Pool pool = getPool();
        (uint160 sqrtPriceX96, , , , , ,) = pool.slot0();

        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 2**96);
        mockOracle.updatePrice(priceX96);
    }

    function setupStrategyParams() public {

        HStrategy.StrategyParams memory strategyParams = HStrategy.StrategyParams({
            halfOfShortInterval: 900,
            tickNeighborhood: 100,
            domainLowerTick: 189000,
            domainUpperTick: 212400
        });

        HStrategy.MintingParams memory mintingParams = HStrategy.MintingParams({
            minToken0ForOpening: 10**4,
            minToken1ForOpening: 10**9
        });

        HStrategy.OracleParams memory oracleParams = HStrategy.OracleParams({
            averagePriceTimeSpan: 150,
            maxTickDeviation: 100
        });

        HStrategy.RatioParams memory ratioParams = HStrategy.RatioParams({
            erc20CapitalRatioD: 50000000,
            minCapitalDeviationD: 10000000,
            minRebalanceDeviationD: 10000000
        });

        vm.startPrank(admin);
        strategy.updateStrategyParams(strategyParams);
        strategy.updateMintingParams(mintingParams);
        strategy.updateOracleParams(oracleParams);
        strategy.updateRatioParams(ratioParams);
        strategy.updateSwapFees(500);
        vm.stopPrank();

    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {
        IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);
        vm.startPrank(admin);
        for (uint256 i = 0; i < nfts.length; ++i) {
            IVaultRegistry(registry).approve(rootGovernance, nfts[i]);
        }
        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(strategy), nfts, admin);
        rootVault = address(w);
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
                strategyTreasury: deployer,
                strategyPerformanceTreasury: deployer,
                managementFee: 2 * 10**7,
                performanceFee: 20 * 10**7,
                privateVault: false,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        vm.warp(block.timestamp + IProtocolGovernance(governance).governanceDelay());
        rootVaultGovernance.commitDelayedStrategyParams(nft);

        vm.stopPrank();
    }

    function setupEnv() public {
        vm.deal(address(this), 0 ether);

        mockOracle = new MockOracle();

        {
            IUniV3VaultGovernance uniV3VaultGovernance = IUniV3VaultGovernance(uniGovernance);

            vm.startPrank(admin);
            uniV3VaultGovernance.stageDelayedProtocolParams(
                IUniV3VaultGovernance.DelayedProtocolParams({
                    positionManager: INonfungiblePositionManager(uniswapV3PositionManager),
                    oracle: IOracle(mockOracle)
                })
            );

            vm.warp(block.timestamp + 86400);
            uniV3VaultGovernance.commitDelayedProtocolParams();
            vm.stopPrank();
        }

        ISwapRouter swapRouter = ISwapRouter(uniswapV3Router);
        INonFungiblePositionManager positionManager = INonFungiblePositionManager(uniswapV3PositionManager);

        IProtocolGovernance protocolGovernance = IProtocolGovernance(governance);

        address[] memory tokens = new address[](2);
        tokens[0] = usdc;
        tokens[1] = weth;

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        uint256 uniV3VaultNft = vaultRegistry.vaultsCount() + 1;

        vm.startPrank(admin);

        {
            IUniV3VaultGovernance uniV3VaultGovernance = IUniV3VaultGovernance(uniGovernance);
            uniV3VaultGovernance.createVault(tokens, admin, 3000, uniHelper);

            IYearnVaultGovernance yearnVaultGovernance = IYearnVaultGovernance(yearnGovernance);
            yearnVaultGovernance.createVault(tokens, admin);
        }

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, admin);
        }

        vm.stopPrank();

        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(uniV3VaultNft + 2));
        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3VaultNft));
        yearnVault = IYearnVault(vaultRegistry.vaultForNft(uniV3VaultNft + 1));

        strategy = new HStrategy(
            positionManager,
            swapRouter,
            uniHelper,
            hHelper
        );

        vm.prank(admin);
        strategy = strategy.createStrategy(
            tokens,
            erc20Vault,
            yearnVault,
            uniV3Vault,
            3000, 
            admin
        );

        setupStrategyParams();

        vm.prank(admin);
        vaultRegistry.approve(address(strategy), uniV3VaultNft);

        vm.prank(admin);
        vaultRegistry.approve(address(strategy), uniV3VaultNft + 1);

        vm.prank(admin);
        vaultRegistry.approve(address(strategy), uniV3VaultNft + 2);

        deal(usdc, address(erc20Vault), 100000 * 10**6); // 100000 USD and 68 WETH
        deal(weth, address(erc20Vault), 68 * 10**18);

        deal(usdc, address(strategy), 10**6); // dust for mints
        deal(weth, address(strategy), 10**15);

        uint256[] memory nfts = new uint256[](3);
        nfts[0] = uniV3VaultNft + 2;
        nfts[1] = uniV3VaultNft;
        nfts[2] = uniV3VaultNft + 1;

        combineVaults(tokens, nfts);
        setOraclePrice();

        rebalance();
    }

    function generateNextPrice() public {
        uint256 nextMultiplier = uint256(feed.getRandom() + 10**9);
        currentPriceD9 = FullMath.mulDiv(currentPriceD9, nextMultiplier, 10**9);
        setOraclePrice();
    }

    function increaseYearnManually() public {
        uint256 profitRateD = yearnAPY / (8*365);
        (uint256[] memory tvlMin, ) = yearnVault.tvl();

        uint256 token0ToDeposit = FullMath.mulDiv(tvlMin[0], profitRateD, 10**9);
        uint256 token1ToDeposit = FullMath.mulDiv(tvlMin[1], profitRateD, 10**9);

        address[] memory tokens = new address[](2);
        uint256[] memory tokenAmounts = new uint256[](2);

        tokens[0] = usdc;
        tokens[1] = weth;
        tokenAmounts[0] = token0ToDeposit;
        tokenAmounts[1] = token1ToDeposit;

        deal(usdc, address(yearnVault), IERC20(usdc).balanceOf(address(yearnVault)) + token0ToDeposit);
        deal(weth, address(yearnVault), IERC20(weth).balanceOf(address(yearnVault)) + token1ToDeposit);

        yearnVault.push(tokens, tokenAmounts, "");
    }

    function swapTokens(
        address sender,
        address recepient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public returns (uint256) {
        uint256 balance = IERC20(tokenIn).balanceOf(sender);
        deal(tokenIn, sender, amountIn);

        IERC20(tokenIn).approve(router, type(uint256).max);

        if (tokenIn == usdc) {
            if (amountIn <= necessarySwapsAmount) {
                necessarySwapsAmount -= amountIn;
            }
            else {
                necessarySwapsAmount = 0;
            }
        }

        uint256 amountOut = ISwapRouter(router).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 3000,
                recipient: recepient,
                deadline: type(uint256).max,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        if (tokenIn == weth) {
            if (amountOut <= necessarySwapsAmount) {
                necessarySwapsAmount -= amountOut;
            }
            else {
                necessarySwapsAmount = 0;
            }
        }

        return amountOut;
    }

    function getTick() public returns (int24) {
        uint256 priceX96 = FullMath.mulDiv(10**21, 2**96, currentPriceD9);
        uint256 sqrtPriceX48 = CommonLibrary.sqrt(priceX96);
        return TickMath.getTickAtSqrtRatio(uint160(sqrtPriceX48 * 2**48));
    }

    function getPool() public returns (IUniswapV3Pool) {
        IUniV3Vault uniVault = strategy.uniV3Vault();
        return uniVault.pool();
    }

    function updateUniswapManually() public {

        int24 tick = getTick();
        int24 currentPoolTick;

        IUniswapV3Pool pool = getPool();
        necessarySwapsAmount = FullMath.mulDiv(usdcIntervalVolume, pool.liquidity(), initialLiquidityAmount);
        uint256 startTry = 500000 * 10**6; // start with 500000 USD

        uint256 needIncrease = 0;
        (, currentPoolTick, , , , , ) = pool.slot0();

        while (currentPoolTick != tick) {

            if (currentPoolTick > tick) { // we have to decrease tick => eth price is low => swap usd to eth
                if (needIncrease == 0) {
                    needIncrease = 1;
                    startTry = startTry / 2;
                }
                swapTokens(deployer, deployer, usdc, weth, startTry);
            } else {
                if (needIncrease == 1) {
                    needIncrease = 0;
                    startTry = startTry / 2;
                }
                swapTokens(deployer, deployer, weth, usdc, FullMath.mulDiv(startTry, 10**21, currentPriceD9));
            }
            (, currentPoolTick, , , , , ) = pool.slot0();
        }

        uint256 remains = necessarySwapsAmount / 2;
        if (remains > 0) {
            uint256 received = swapTokens(deployer, deployer, usdc, weth, remains);
            swapTokens(deployer, deployer, weth, usdc, received);
        }
    }

    function testH() public {

        setupEnv();
        feed.parseFile();

        IUniswapV3Pool pool = getPool();
        initialLiquidityAmount = pool.liquidity();

        uint256 initialTvl = getUSDTvl();

        for (uint256 i = 0; i < 180 * 8; ++i) {
            
            generateNextPrice();
            increaseYearnManually();
            updateUniswapManually();
            rebalance();

            if (currentPriceD9 < minEthPrice) {
                minEthPrice = currentPriceD9;
            }

            if (currentPriceD9 > maxEthPrice) {
                maxEthPrice = currentPriceD9;
            }
        }

        console2.log("MIN ETH PRICE WAS", minEthPrice / 10**9);
        console2.log("MAX ETH PRICE WAS", maxEthPrice / 10**9);
        console2.log("FINAL PRICE WAS", currentPriceD9 / 10**9);
        
        int256 profit = int256(getUSDTvl()) - int256(initialTvl);
        int256 pnProfit = int256(getUSDPNTvl()) - int256(initialTvl);

        if (profit > 0) {
            console2.log("PROFIT WAS", 100 * uint256(profit) / initialTvl, "%");
        }
        else {
            console2.log("PROFIT WAS -", 100 * uint256(-profit) / initialTvl, "%");
        }


        if (pnProfit > 0) {
            console2.log("PRICE NEUTRAL PROFIT WAS", 100 * uint256(pnProfit) / initialTvl, "%");
        }
        else {
            console2.log("PRICE NEUTRAL PROFIT WAS -", 100 * uint256(-pnProfit) / initialTvl, "%");
        }
        
    }
}
