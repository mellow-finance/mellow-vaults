// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../lib/forge-std/src/console2.sol";
import "../lib/forge-std/src/Vm.sol";
import "../lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../test/helpers/IWETH.sol";
import "../test/helpers/IWSTETH.sol";
import "../test/helpers/ISTETH.sol";
import "../test/helpers/ICurvePool.sol";
import "../test/helpers/ISwapRouter.sol";
import "../test/helpers/INonFungiblePositionManager.sol";
import "../test/helpers/IProtocolGovernance.sol";
import "../test/helpers/IUniV3Helper.sol";
import "../test/helpers/ILStrategyHelper.sol";
import "../test/helpers/IVaultRegistry.sol";
import "../test/helpers/IUniV3VaultGovernance.sol";
import "../test/helpers/IERC20VaultGovernance.sol";
import "../test/helpers/IERC20RootVaultGovernance.sol";
import "../test/helpers/libraries/PermissionIdsLibrary.sol";
import "../src/MockCowswap.sol";
import "../src/LStrategy.sol";
import "../src/ERC20Validator.sol";
import "../src/CowSwapValidator.sol";
import "../src/MockOracle.sol";
import "./Constants.sol";
import "./FeedContract.sol";

contract Backtest is Test {
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniswapV3PositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public deployer = address(this);
    address public admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;
    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public helper = 0x1E13A22d392584B24f5DDd6E6Da88f54dA872FA8;
    address public uniGovernance = 0x8306bec30063f00F5ffd6976f09F6b10E77B27F2;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public lStrategyHelper = 0x9Cf7dFEf7C0311C16C864e8B88bf3261F19a6DB8;
    address public router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public mockOracleAddress;
    LStrategy lstrategy;

    address public rootVault;

    uint256 constant Q48 = 2**48;
    uint256 constant Q96 = 2**96;
    uint256 constant D27 = 10**27;
    uint256 constant D18 = 10**18;
    uint256 constant D10 = 10**10;
    uint256 constant D9 = 10**9;

    uint256 erc20UniV3Gas;
    uint256 erc20RebalanceCount;
    uint256 uniV3Gas;
    uint256 uniV3RebalanceCount;

    function mint(
        address token,
        address addr,
        uint256 amount
    ) public {
        uint256 currentBalance = IERC20(token).balanceOf(addr);
        deal(token, addr, currentBalance + amount);
    }

    function initialMint() public payable {
        uint256 smallAmount = 10**13;
        mint(weth, deployer, smallAmount);

        IWETH wethContract = IWETH(weth);
        IWSTETH wstethContract = IWSTETH(wsteth);
        ICurvePool curvePool = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
        IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

        wethContract.approve(address(curvePool), type(uint256).max);
        steth.approve(address(wstethContract), type(uint256).max);

        wethContract.withdraw(smallAmount / 2);
        curvePool.exchange{value: smallAmount / 2}(0, 1, smallAmount / 2, 0);
        wstethContract.wrap(((smallAmount / 2) * 99) / 100);
    }

    fallback() external payable {}

    receive() external payable {}

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    ) external returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {
        IERC20RootVaultGovernance rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);
        vm.startPrank(admin);
        for (uint256 i = 0; i < nfts.length; ++i) {
            IVaultRegistry(registry).approve(rootGovernance, nfts[i]);
        }
        (IERC20RootVault w, uint256 nft) = rootVaultGovernance.createVault(tokens, address(lstrategy), nfts, admin);
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

    function setupSecondPhase(IWETH wethContract, IWSTETH wstethContract) public payable {
        ICurvePool curvePool = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
        IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

        wethContract.approve(address(curvePool), type(uint256).max);
        steth.approve(address(wstethContract), type(uint256).max);
        wethContract.withdraw(2 * 10**21);

        console2.log("Before exchange");
        curvePool.exchange{value: 2 * 10**21}(0, 1, 2 * 10**21, 0);
        console2.log("After exchange");

        wstethContract.wrap(10**18 * 1990);

        console2.log("After wrap");

        wstethContract.transfer(address(lstrategy), 3 * 10**17);
        wethContract.transfer(address(lstrategy), 3 * 10**17);

        MockOracle mockOracle = new MockOracle();
        mockOracleAddress = address(mockOracle);
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

        lstrategy.updateTradingParams(
            LStrategy.TradingParams({
                maxSlippageD: 10**7,
                oracleSafetyMask: 0x20,
                orderDeadline: 86400 * 30,
                oracle: mockOracle,
                maxFee0: 10**9,
                maxFee1: 10**9
            })
        );

        lstrategy.updateRatioParams(
            LStrategy.RatioParams({
                erc20UniV3CapitalRatioD: 5 * 10**7, // 0.05 * DENOMINATOR
                erc20TokenRatioD: 5 * 10**8, // 0.5 * DENOMINATOR
                minErc20UniV3CapitalRatioDeviationD: 10**7,
                minErc20TokenRatioDeviationD: 5 * 10**7,
                minUniV3LiquidityRatioDeviationD: 2 * 10**6
            })
        );

        lstrategy.updateOtherParams(
            LStrategy.OtherParams({minToken0ForOpening: 10**6, minToken1ForOpening: 10**6, secondsBetweenRebalances: 0})
        );

        vm.stopPrank();
    }

    function setup() public payable returns (uint256 startNft) {
        vm.deal(address(this), 0 ether);
        initialMint();
        console2.log("In setup");

        uint256 uniV3PoolFee = 500;
        ISwapRouter swapRouter = ISwapRouter(uniswapV3Router);
        INonFungiblePositionManager positionManager = INonFungiblePositionManager(uniswapV3PositionManager);

        IWETH wethContract = IWETH(weth);
        IWSTETH wstethContract = IWSTETH(wsteth);

        wethContract.approve(uniswapV3PositionManager, type(uint256).max);
        wstethContract.approve(uniswapV3PositionManager, type(uint256).max);

        IProtocolGovernance protocolGovernance = IProtocolGovernance(governance);

        {
            uint8[] memory args = new uint8[](1);
            args[0] = PermissionIdsLibrary.ERC20_VAULT_TOKEN;
            vm.prank(admin);
            protocolGovernance.stagePermissionGrants(wsteth, args);
        }

        vm.warp(block.timestamp + protocolGovernance.governanceDelay());
        vm.prank(admin);
        protocolGovernance.commitPermissionGrants(wsteth);

        address[] memory tokens = new address[](2);
        tokens[0] = wsteth;
        tokens[1] = weth;

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        uint256 uniV3LowerVaultNft = vaultRegistry.vaultsCount() + 1;

        vm.startPrank(admin);

        {
            IUniV3VaultGovernance uniV3VaultGovernance = IUniV3VaultGovernance(uniGovernance);
            uniV3VaultGovernance.createVault(tokens, admin, uint24(uniV3PoolFee), helper);
            uniV3VaultGovernance.createVault(tokens, admin, uint24(uniV3PoolFee), helper);
        }

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, admin);
            IVaultGovernance.InternalParams memory kek = erc20VaultGovernance.internalParams();
        }

        vm.stopPrank();

        MockCowswap mockCowswap = new MockCowswap();
        IERC20Vault erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 2));
        IUniV3Vault uniV3LowerVault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft));
        IUniV3Vault uniV3UpperVault = IUniV3Vault(vaultRegistry.vaultForNft(uniV3LowerVaultNft + 1));

        lstrategy = new LStrategy(
            positionManager,
            address(mockCowswap),
            erc20Vault,
            uniV3LowerVault,
            uniV3UpperVault,
            ILStrategyHelper(lStrategyHelper),
            admin,
            uint16(Constants.width)
        );
        ERC20Validator wstethValidator = new ERC20Validator(IProtocolGovernance(governance));

        vm.startPrank(admin);
        protocolGovernance.stageValidator(wsteth, address(wstethValidator));
        vm.warp(block.timestamp + protocolGovernance.governanceDelay());
        protocolGovernance.commitValidator(wsteth);

        CowswapValidator cowswapValidator = new CowswapValidator(protocolGovernance);

        protocolGovernance.stageValidator(address(mockCowswap), address(cowswapValidator));
        vm.warp(block.timestamp + protocolGovernance.governanceDelay());
        protocolGovernance.commitValidator(address(mockCowswap));

        vm.stopPrank();

        console2.log("Minted lstrategy");
        mint(weth, deployer, 4 * 10**21);
        console2.log("Minted money");

        setupSecondPhase(wethContract, wstethContract);
        return uniV3LowerVaultNft;
    }

    function mintMockPosition() public {
        INonFungiblePositionManager positionManager = INonFungiblePositionManager(uniswapV3PositionManager);
        positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: wsteth,
                token1: weth,
                fee: 500,
                tickLower: -10000,
                tickUpper: 10000,
                amount0Desired: 5 * 10**20,
                amount1Desired: 5 * 10**20,
                amount0Min: 0,
                amount1Min: 0,
                recipient: deployer,
                deadline: type(uint256).max
            })
        );
    }

    // rawPrice = realPrice * 10^27
    // returnPrice = sqrt(realPrice) * 2^96
    function stringToSqrtPriceX96(uint256 rawPrice) public returns (uint256 price) {
        uint256 priceX96 = FullMath.mulDiv(rawPrice, Q96, D27);
        uint256 sqrtPriceX48 = CommonLibrary.sqrt(priceX96);
        return sqrtPriceX48 * Q48;
    }

    function stringToPriceX96(uint256 rawPrice) public returns (uint256 price) {
        uint256 priceX96 = FullMath.mulDiv(rawPrice, Q96, D27);
        return priceX96;
    }

    function getTick(uint256 x) public returns (int24) {
        console2.log(x);
        return TickMath.getTickAtSqrtRatio(uint160(x));
    }

    function getPool() public returns (IUniswapV3Pool) {
        IUniV3Vault lowerVault = lstrategy.lowerVault();
        return lowerVault.pool();
    }

    function swapTokens(
        address sender,
        address recepient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public {
        uint256 balance = IERC20(tokenIn).balanceOf(sender);
        if (balance < amountIn) {
            if (tokenIn == weth) {
                mint(tokenIn, sender, amountIn - balance);
            } else {
                ISTETH stethContract = ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
                while (balance < amountIn) {
                    uint256 toMint = 10**17 * 10001;
                    mint(weth, sender, amountIn - balance);
                    IWETH(weth).withdraw(toMint);
                    stethContract.submit{value: 10**21}(deployer);
                    IWSTETH(wsteth).wrap(toMint);
                    IWSTETH(wsteth).transfer(sender, toMint);
                    balance = IERC20(tokenIn).balanceOf(sender);
                }
            }
        }

        vm.startPrank(sender);

        IERC20(tokenIn).approve(router, type(uint256).max);

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

        vm.stopPrank();
    }

    function changePrice(int24 tick) public {
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        MockOracle(mockOracleAddress).updatePrice(priceX96);
    }

    function makeDesiredPoolPrice(int24 tick) public {
        IUniswapV3Pool pool = getPool();
        uint256 startTry = 10**18;

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

    function fullPriceUpdate(int24 tick) public {
        makeDesiredPoolPrice(tick);
        changePrice(tick);
    }

    function getUniV3Price() public returns (uint256) {
        IUniswapV3Pool pool = getPool();
        (uint256 sqrtPriceX96, , , , , , ) = pool.slot0();
        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
    }

    function getUniV3Tick() public returns (int24) {
        IUniswapV3Pool pool = getPool();
        (, int24 tick, , , , , ) = pool.slot0();
        return tick;
    }

    function preparePush(
        IUniV3Vault vault,
        int24 tickLower,
        int24 tickUpper
    ) public {
        vm.startPrank(admin);
        IVaultRegistry(registry).approve(deployer, vault.nft());
        vm.stopPrank();

        (uint256 nft, , , ) = INonFungiblePositionManager(uniswapV3PositionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: wsteth,
                token1: weth,
                fee: 500,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: 10**9,
                amount1Desired: 10**9,
                amount0Min: 0,
                amount1Min: 0,
                recipient: deployer,
                deadline: type(uint256).max
            })
        );

        INonFungiblePositionManager(uniswapV3PositionManager).safeTransferFrom(deployer, address(vault), nft);
    }

    function buildInitialPositions(
        uint256 width,
        uint256 weth_amount,
        uint256 wsteth_amount,
        uint256 startNft
    ) public {
        int24 tick = getUniV3Tick();
        changePrice(tick);

        int24 semiPositionRange = int24(int256(width)) / 2;
        int24 tickLeftLower = (tick / semiPositionRange) * semiPositionRange - semiPositionRange;
        int24 tickLeftUpper = tickLeftLower + 2 * semiPositionRange;

        int24 tickRightLower = tickLeftLower + semiPositionRange;
        int24 tickRightUpper = tickLeftUpper + semiPositionRange;

        IUniV3Vault lowerVault = lstrategy.lowerVault();
        IUniV3Vault upperVault = lstrategy.upperVault();

        preparePush(lowerVault, tickLeftLower, tickLeftUpper);
        preparePush(upperVault, tickRightLower, tickRightUpper);

        {
            uint256[] memory nfts = new uint256[](3);
            nfts[0] = startNft + 2;
            nfts[1] = startNft;
            nfts[2] = startNft + 1;

            address[] memory tokens = new address[](2);
            tokens[0] = wsteth;
            tokens[1] = weth;

            combineVaults(tokens, nfts);
        }

        IERC20Vault erc20 = lstrategy.erc20Vault();
        while (IERC20(weth).balanceOf(deployer) < 10**18 * (weth_amount + 10)) {
            mint(weth, deployer, 10**21);
        }

        IWETH(weth).transfer(address(erc20), 10**18 * weth_amount);

        ISTETH stethContract = ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        IWSTETH wstethContract = IWSTETH(wsteth);

        while (wstethContract.balanceOf(deployer) < 10**18 * (wsteth_amount + 10)) {
            mint(weth, deployer, 10**21);
            IWETH(weth).withdraw(10**21);
            stethContract.submit{value: 10**21}(deployer);
            wstethContract.wrap(10**21);
        }

        IWSTETH(wsteth).transfer(address(erc20), 10**18 * wsteth_amount);
    }

    function getCapital(uint256 priceX96, address vault) public returns (uint256) {
        (uint256[] memory minTvl, uint256[] memory maxTvl) = IVault(vault).tvl();
        return FullMath.mulDiv((minTvl[0] + maxTvl[0]) / 2, priceX96, Q96) + (minTvl[1] + maxTvl[1]) / 2;
    }

    function assureEquality(uint256 x, uint256 y) public returns (bool) {
        if (x >= y) {
            uint256 delta = x - y;
            if (delta * 100 < x) {
                return true;
            }
            return false;
        } else {
            uint256 delta = y - x;
            if (delta * 100 < y) {
                return true;
            }
            return false;
        }
    }

    function mintForDeployer(
        ISTETH stethContract,
        IWETH wethContract,
        uint256 toMintEth,
        uint256 toMintSteth
    ) public {
        uint256 startEth = deployer.balance;
        uint256 startSteth = stethContract.balanceOf(deployer);

        while (true) {
            uint256 currentSteth = stethContract.balanceOf(deployer);
            int256 balanceDiff = int256(currentSteth) - int256(startSteth) - int256(toMintSteth);
            if (balanceDiff >= 0) {
                break;
            }

            mint(weth, deployer, 10**21);
            wethContract.withdraw(10**21);
            stethContract.submit{value: 10**21}(deployer);
        }

        while (true) {
            uint256 currentEth = deployer.balance;
            int256 balanceDiff = int256(currentEth) - int256(startEth) - int256(toMintEth);
            if (balanceDiff >= 0) {
                break;
            }
            mint(weth, deployer, 10**21);
            wethContract.withdraw(10**21);
        }
    }

    function mintForPool(
        uint256 toMintEth,
        uint256 toMintSteth,
        IWETH wethContract,
        IWSTETH wstethContract,
        ISTETH stethContract,
        ICurvePool curvePool
    ) public {
        mintForDeployer(stethContract, wethContract, toMintEth + 10**17, toMintSteth);
        stethContract.approve(address(curvePool), type(uint256).max);
        console2.log("Before adding liquidity");
        console2.log("toMintEth: ", toMintEth);
        console2.log("toMintSteth: ", toMintSteth);
        console2.log("eth balance: ", deployer.balance);
        console2.log("steth balance: ", stethContract.balanceOf(deployer));

        uint256[N_COINS] memory args;
        args[0] = toMintEth;
        args[1] = toMintSteth;

        curvePool.add_liquidity{value: toMintEth}(args, 0);
        console2.log("After adding liquidity");
    }

    function exchange(
        uint256 amountIn,
        uint256 stethAmountInPool,
        uint256 wethAmountInPool,
        uint256 stEthPerToken,
        bool wstethToWeth
    )
        public
        returns (
            uint256 expectedOut,
            uint256 swapFees,
            int256 slippageFees
        )
    {
        uint256 poolEthBalance = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).balances(0);
        uint256 poolStethBalance = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).balances(1);

        uint256 newPoolEth;
        uint256 newPoolSteth;

        {
            uint256 firstMultiplier = poolEthBalance * stethAmountInPool;
            uint256 secondMultiplier = poolStethBalance * wethAmountInPool;

            newPoolEth = poolEthBalance;
            newPoolSteth = poolStethBalance;

            if (firstMultiplier < secondMultiplier) {
                newPoolEth = secondMultiplier / stethAmountInPool;
            }
            if (secondMultiplier < firstMultiplier) {
                newPoolSteth = firstMultiplier / wethAmountInPool;
            }
        }

        mintForPool(
            newPoolEth - poolEthBalance,
            newPoolSteth - poolStethBalance,
            IWETH(weth),
            IWSTETH(wsteth),
            ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84),
            ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022)
        );
        {
            uint256 firstMultiplier = (ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).balances(0)) *
                stethAmountInPool;
            uint256 secondMultiplier = (ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).balances(1)) *
                wethAmountInPool;

            if (firstMultiplier <= secondMultiplier) {
                require((secondMultiplier - firstMultiplier) * 1000 < secondMultiplier);
            } else {
                require((firstMultiplier - secondMultiplier) * 1000 < firstMultiplier);
            }
        }

        if (wstethToWeth) {
            if (stEthPerToken < 10**18) {
                console2.log("stEthPerToken alert: ", stEthPerToken);
            }

            uint256 adjustedVal = FullMath.mulDiv(
                FullMath.mulDiv(amountIn, stEthPerToken, D18),
                newPoolEth,
                wethAmountInPool
            ) / Constants.poolScale;

            uint256 balance = ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).balanceOf(deployer);
            if (balance * 10 < adjustedVal * 11) {
                mintForDeployer(
                    ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84),
                    IWETH(weth),
                    0,
                    (adjustedVal * 11) / 10 - balance
                );
            }

            if (adjustedVal > 0) {
                console2.log("Before steth->eth swap");
                console2.log("Balance: ", ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).balanceOf(deployer));
                console2.log("Needed: ", adjustedVal);
                expectedOut = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).exchange(1, 0, adjustedVal, 0);
                ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).exchange{value: expectedOut}(
                    0,
                    1,
                    expectedOut,
                    0
                ); // money back
                console2.log("After steth->eth swap");
            }

            uint256 fees = FullMath.mulDiv(
                expectedOut,
                ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).fee(),
                D10 - ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).fee()
            );
            {
                uint256 expectedWithoutSlippage;
                uint256 amountToCalc = D18;

                if (amountToCalc > adjustedVal) {
                    amountToCalc = adjustedVal;
                }

                expectedWithoutSlippage = FullMath.mulDiv(
                    FullMath.mulDiv(
                        ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).get_dy(1, 0, amountToCalc),
                        adjustedVal,
                        amountToCalc
                    ),
                    D10,
                    D10 - ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).fee()
                );

                slippageFees = int256(expectedWithoutSlippage) - int256(fees) - int256(expectedOut);
            }

            if (slippageFees < 0) {
                console2.log("adjustedVal: ", adjustedVal);
                console2.log("result: ", expectedOut);
                console2.log("swap fees: ", fees);
            }

            expectedOut = FullMath.mulDiv(expectedOut, wethAmountInPool, newPoolEth) * Constants.poolScale;
            swapFees = FullMath.mulDiv(fees, wethAmountInPool, newPoolEth) * Constants.poolScale;
            if (slippageFees > 0) {
                slippageFees = int256(
                    FullMath.mulDiv(uint256(slippageFees), wethAmountInPool, newPoolEth) * Constants.poolScale
                );
            } else {
                slippageFees = -int256(
                    FullMath.mulDiv(uint256(-slippageFees), wethAmountInPool, newPoolEth) * Constants.poolScale
                );
            }
        } else {
            uint256 adjustedVal;

            {
                uint256 valWeth = amountIn;
                adjustedVal = FullMath.mulDiv(valWeth, newPoolEth, wethAmountInPool) / Constants.poolScale;
            }

            if (deployer.balance * 10 < adjustedVal * 11) {
                mintForDeployer(
                    ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84),
                    IWETH(weth),
                    (adjustedVal * 11) / 10 - deployer.balance,
                    0
                );
            }

            uint256 valSteth = 0;

            if (adjustedVal > 0) {
                console2.log("Before eth->steth swap");
                console2.log("Balance: ", deployer.balance);
                console2.log("Adjusted val: ", adjustedVal);
                valSteth = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).exchange{value: adjustedVal}(
                    0,
                    1,
                    adjustedVal,
                    0
                );
                ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).exchange(1, 0, valSteth, 0); // money back
                console2.log("After eth->steth swap");
            }

            if (stEthPerToken < 10**18) {
                console2.log("stEthPerToken alert: ", stEthPerToken);
            }

            expectedOut = FullMath.mulDiv(valSteth, D18, stEthPerToken);

            uint256 fees = FullMath.mulDiv(
                expectedOut,
                ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).fee(),
                D10 - ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).fee()
            );
            {
                uint256 amountToCalc = D18;

                if (amountToCalc > adjustedVal) {
                    amountToCalc = adjustedVal;
                }

                uint256 expectedWithoutSlippage = FullMath.mulDiv(
                    FullMath.mulDiv(
                        ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).get_dy(0, 1, amountToCalc),
                        adjustedVal,
                        amountToCalc
                    ),
                    D10,
                    D10 - ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022).fee()
                );
                slippageFees = int256(expectedWithoutSlippage) - int256(fees) - int256(expectedOut);
            }

            if (slippageFees < 0) {
                console2.log("adjustedVal: ", adjustedVal);
                console2.log("result: ", expectedOut);
                console2.log("swap fees: ", fees);
            }

            expectedOut = FullMath.mulDiv(expectedOut, wethAmountInPool, newPoolEth) * Constants.poolScale;
            swapFees = FullMath.mulDiv(fees, wethAmountInPool, newPoolEth) * Constants.poolScale;
            if (slippageFees > 0) {
                slippageFees = int256(
                    FullMath.mulDiv(uint256(slippageFees), wethAmountInPool, newPoolEth) * Constants.poolScale
                );
            } else {
                slippageFees = -int256(
                    FullMath.mulDiv(uint256(-slippageFees), wethAmountInPool, newPoolEth) * Constants.poolScale
                );
            }
        }
    }

    function swapWethToWsteth(
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 stethAmountInPool,
        uint256 wethAmountInPool,
        uint256 stEthPerToken
    )
        public
        returns (
            string memory tokenIn,
            string memory tokenOut,
            uint256 realAmountIn,
            uint256 amountOut,
            uint256 swapFees,
            int256 slippageFees
        )
    {
        address erc20Address = address(lstrategy.erc20Vault());
        uint256 expectedOut;

        (expectedOut, swapFees, slippageFees) = exchange(
            amountIn,
            stethAmountInPool,
            wethAmountInPool,
            stEthPerToken,
            false
        );
        while (IWSTETH(wsteth).balanceOf(deployer) < (expectedOut * 11) / 10) {
            mint(weth, deployer, 10**21);
            IWETH(weth).withdraw(10**21);
            ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).submit{value: 10**21}(deployer);
            IWSTETH(wsteth).wrap(10**21);
        }

        if (expectedOut < minAmountOut) {
            console2.log("Expected out less than minAmountOut weth=>wsteth");
            tokenIn = "weth";
            tokenOut = "wsteth";
        } else {
            vm.startPrank(erc20Address);
            IWETH(weth).transfer(deployer, amountIn);
            vm.stopPrank();
            IWSTETH(wsteth).transfer(erc20Address, expectedOut);

            tokenIn = "weth";
            tokenOut = "wsteth";
            realAmountIn = amountIn;
        }
    }

    function swapWstethToWeth(
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 stethAmountInPool,
        uint256 wethAmountInPool,
        uint256 stEthPerToken
    )
        public
        returns (
            string memory tokenIn,
            string memory tokenOut,
            uint256 realAmountIn,
            uint256 amountOut,
            uint256 swapFees,
            int256 slippageFees
        )
    {
        address erc20Address = address(lstrategy.erc20Vault());
        uint256 expectedOut;

        (expectedOut, swapFees, slippageFees) = exchange(
            amountIn,
            stethAmountInPool,
            wethAmountInPool,
            stEthPerToken,
            true
        );
        while (IWETH(weth).balanceOf(deployer) < (expectedOut * 11) / 10) {
            mint(weth, deployer, 10**21);
        }

        if (expectedOut < minAmountOut) {
            console2.log("Expected out less than minAmountOut wsteth=>weth");
            tokenIn = "wsteth";
            tokenOut = "weth";
        } else {
            vm.startPrank(erc20Address);
            IWSTETH(wsteth).transfer(deployer, amountIn);
            vm.stopPrank();
            IWETH(weth).transfer(erc20Address, expectedOut);

            tokenIn = "wsteth";
            tokenOut = "weth";
            realAmountIn = amountIn;
        }
    }

    function swapOnCowswap(
        uint256 stethAmountInPool,
        uint256 wethAmountInPool,
        uint256 stEthPerToken,
        ICurvePool curvePool
    )
        public
        returns (
            string memory tokenIn,
            string memory tokenOut,
            uint256 amountIn,
            uint256 amountOut,
            uint256 swapFees,
            int256 slippageFees
        )
    {
        vm.startPrank(admin);
        lstrategy.postPreOrder(0);
        vm.stopPrank();

        (address preOrderTokenIn, , , uint256 preOrderAmountIn, uint256 preOrderMinAmountOut) = lstrategy.preOrder();
        if (preOrderAmountIn == 0) {
            tokenIn = "weth";
            tokenOut = "wsteth";
        } else {
            if (preOrderTokenIn == weth) {
                (tokenIn, tokenOut, amountIn, amountOut, swapFees, slippageFees) = swapWethToWsteth(
                    preOrderAmountIn,
                    preOrderMinAmountOut,
                    stethAmountInPool,
                    wethAmountInPool,
                    stEthPerToken
                );
            } else {
                (tokenIn, tokenOut, amountIn, amountOut, swapFees, slippageFees) = swapWstethToWeth(
                    preOrderAmountIn,
                    preOrderMinAmountOut,
                    stethAmountInPool,
                    wethAmountInPool,
                    stEthPerToken
                );
            }
        }
    }

    function ERC20UniRebalance(
        uint256 priceX96,
        uint256 wstethAmount,
        uint256 wethAmount,
        uint256 stEthPerToken
    ) public {
        uint256 i = 0;

        while (true) {
            uint256 capitalErc20 = getCapital(priceX96, address(lstrategy.erc20Vault()));
            uint256 capitalLower = getCapital(priceX96, address(lstrategy.lowerVault()));
            uint256 capitalUpper = getCapital(priceX96, address(lstrategy.upperVault()));

            if (assureEquality(capitalErc20 * 19, capitalLower + capitalUpper)) {
                break;
            }

            vm.startPrank(admin);

            uint256[] memory arr = new uint256[](2);
            uint256 gasBefore = gasleft();
            lstrategy.rebalanceERC20UniV3Vaults(arr, arr, type(uint256).max);
            uint256 gasAfter = gasleft();
            erc20RebalanceCount += 1;
            erc20UniV3Gas += gasBefore - gasAfter;

            vm.stopPrank();

            ICurvePool curvePool = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
            IWETH wethContract = IWETH(weth);
            IWSTETH wstethContract = IWSTETH(wsteth);
            ISTETH stethContract = ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

            swapOnCowswap(wstethAmount, wethAmount, stEthPerToken, curvePool);
            i += 1;

            if (i >= 10) {
                console2.log("More than 10 iterations of rebalanceERC20UniV3Vaults needed!");
                break;
            }
        }
    }

    function getExpectedRatio() public returns (uint256) {
        address[] memory tokens = new address[](2);
        tokens[0] = wsteth;
        tokens[1] = weth;

        (IOracle p1, uint32 p2, uint32 p3, uint256 p4, uint256 p5, uint256 p6) = lstrategy.tradingParams();
        LStrategy.TradingParams memory pp = LStrategy.TradingParams({
            oracle: p1,
            maxSlippageD: p2,
            orderDeadline: p3,
            oracleSafetyMask: p4,
            maxFee0: p5,
            maxFee1: p6
        });

        uint256 targetPriceX96 = lstrategy.getTargetPriceX96(tokens[0], tokens[1], pp);
        uint256 sqrtTargetPriceX48 = CommonLibrary.sqrt(targetPriceX96);

        int24 targetTick = TickMath.getTickAtSqrtRatio(uint160(sqrtTargetPriceX48 * Q48));
        (uint256 neededRatio, ) = lstrategy.targetUniV3LiquidityRatio(targetTick);

        return neededRatio;
    }

    function getVaultsLiquidityRatio() public returns (uint256) {
        IUniV3Vault lowerVault = lstrategy.lowerVault();
        IUniV3Vault upperVault = lstrategy.upperVault();

        (,,,,,,, uint128 lowerVaultLiquidity, , , ,) = INonFungiblePositionManager(uniswapV3PositionManager).positions(lowerVault.uniV3Nft());
        (,,,,,,, uint128 upperVaultLiquidity, , , ,) = INonFungiblePositionManager(uniswapV3PositionManager).positions(upperVault.uniV3Nft());

        uint256 total = uint256(lowerVaultLiquidity) + uint256(upperVaultLiquidity);
        return D9 - FullMath.mulDiv(uint256(lowerVaultLiquidity), D9, total);
    }

    function uniV3Balance() public returns (bool) {
        uint256 neededRatio = getExpectedRatio();
        uint256 currentRatio = getVaultsLiquidityRatio();

        uint256 delta;
        if (neededRatio < currentRatio) {
            delta = currentRatio - neededRatio;
        } else {
            delta = neededRatio - currentRatio;
        }

        if (delta < 5 * 10**7) {
            return true;
        }
        return false;
    }

    function makeRebalances(
        uint256 priceX96,
        uint256 wstethAmount,
        uint256 wethAmount,
        uint256 stEthPerToken
    ) public {
        bool wasRebalance = false;
        uint256 iter = 0;

        while (!uniV3Balance()) {
            wasRebalance = true;
            vm.startPrank(admin);
            uint256[] memory arr = new uint256[](2);
            uint256 gasBefore = gasleft();
            lstrategy.rebalanceUniV3Vaults(arr, arr, type(uint256).max);
            uint256 gasAfter = gasleft();

            uniV3Gas += gasBefore - gasAfter;
            uniV3RebalanceCount += 1;

            gasBefore = gasleft();
            lstrategy.rebalanceERC20UniV3Vaults(arr, arr, type(uint256).max);
            gasAfter = gasleft();

            vm.stopPrank();

            erc20UniV3Gas += gasBefore - gasAfter;
            erc20RebalanceCount += 1;

            swapOnCowswap(wstethAmount, wethAmount, stEthPerToken, ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022));
            iter += 1;
            if (iter >= 10) {
                console2.log(
                    "More than 20 iterations of rebalance needed needed!!!"
                );
                break;
            }

        }

        if (wasRebalance) {
            ERC20UniRebalance(priceX96, wstethAmount, wethAmount, stEthPerToken);
        }
    }

    function execute(
        uint256 width,
        uint256 weth_amount,
        uint256 wsteth_amount,
        uint256 startNft
    ) public {
        console2.log("Process started");

        mintMockPosition();
        Feed feed = new Feed();
        (
            uint256[] memory blocks,
            uint256[] memory prices,
            uint256[] memory stethAmounts,
            uint256[] memory wethAmounts,
            uint256[] memory stEthPerToken
        ) = feed.parseFile();

        console2.log("Before price update");
        fullPriceUpdate(getTick(stringToSqrtPriceX96(prices[0])));
        console2.log("After price update");
        console2.log("Price is ", getUniV3Price());

        buildInitialPositions(width, weth_amount, wsteth_amount, startNft);

        ERC20UniRebalance(stringToSqrtPriceX96(prices[0]), stethAmounts[0], wethAmounts[0], stEthPerToken[0]);

        uint256 prev_block = 0;
        for (uint256 i = 1; i < prices.length; ++i) {
            console2.log(gasleft());
            console2.log(i);
            if (blocks[i] - prev_block > 86400 / 15) {
                console2.log("MAKE REBALANCE");
                makeRebalances(stringToPriceX96(prices[i]), stethAmounts[i], wethAmounts[i], stEthPerToken[i]);
                prev_block = blocks[i];
            }
            if (i % 500 == 0) {
                console2.log("Iteration: ", i);
                console2.log("ERC20Rebalances: ", erc20RebalanceCount);
                console2.log("UniV3 rebalances: ", uniV3RebalanceCount);
                console2.log("UniV3 used: ", uniV3Gas);
                console2.log("ERC20UniV3 used: ", erc20UniV3Gas);
            }

            fullPriceUpdate(getTick(stringToSqrtPriceX96(prices[i])));
            (uint256[] memory minTvl, uint256[] memory maxTvl) = IERC20RootVault(rootVault).tvl();
            console2.log("WSTETH", minTvl[0]);
            console2.log("WETH", minTvl[1]);
        }

        console2.log("ERC20Rebalances: ", erc20RebalanceCount);
        console2.log("UniV3 rebalances: ", uniV3RebalanceCount);
        console2.log("UniV3 used: ", uniV3Gas);
        console2.log("ERC20UniV3 used: ", erc20UniV3Gas);
    }

    function test() public {
        uint256 nft = setup();
        execute(Constants.width, Constants.wethAmount, Constants.wstethAmount, nft);
    }
}
