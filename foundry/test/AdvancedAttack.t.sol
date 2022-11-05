// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../lib/forge-std/src/console2.sol";
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
    
    address rootVault;
    LStrategy lstrategy;

    uint256 constant Q96 = 1 << 96;

    function setupUniGovernance() public {
        UniV3VaultSpot spotVault = new UniV3VaultSpot();
        IVaultGovernance.InternalParams memory params_ = IVaultGovernance.InternalParams(IProtocolGovernance(governance), IVaultRegistry(registry), IVault(spotVault));
        IUniV3VaultGovernance.DelayedProtocolParams memory protocolParams_ = IUniV3VaultGovernance(uniGovernanceOld).delayedProtocolParams();
        uniGovernance = address(new UniV3VaultSpotGovernance(params_, protocolParams_));
        vm.startPrank(admin);
        uint8[] memory permissions = new uint8[](2);
        permissions[0] = PermissionIdsLibrary.CREATE_VAULT;
        permissions[1] = PermissionIdsLibrary.REGISTER_VAULT;
        IProtocolGovernance(governance).stagePermissionGrants(
            uniGovernance,
            permissions
        );
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

        mint(weth, deployer, 10 ** 10);
        mint(wsteth, deployer, 10 ** 10);
        IERC20(weth).approve(rootVault, 10 ** 10);
        IERC20(wsteth).approve(rootVault, 10 ** 10);
        uint256[] memory toDeposit = new uint256[](2);
        toDeposit[0] = 10 ** 10;
        toDeposit[1] = 10 ** 10;
        w.deposit(toDeposit, 0, "");
    }

    function setupSecondPhase(IWETH wethContract, IWSTETH wstethContract) public payable {
        ICurvePool curvePool = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
        IERC20 steth = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

        wethContract.approve(address(curvePool), type(uint256).max);
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

    function getCapital(uint256 amount0, uint256 amount1, int24 currentTick) internal pure returns (uint256 capital) {
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(currentTick);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 2 ** 96);
        // TODO: check order
        return FullMath.mulDiv(amount0, priceX96, 2 ** 96) + amount1;
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

    function tvl(
        int24 leftTick,
        int24 rightTick,
        int24 currentTick,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(currentTick),
            TickMath.getSqrtRatioAtTick(leftTick),
            TickMath.getSqrtRatioAtTick(rightTick),
            liquidity
        );
    }

    function getCapitalAtCurrentTick(
        int24 leftLowerTick,
        int24 leftUpperTick,
        int24 rightLowerTick,
        int24 rightUpperTick,
        int24 currentTick,
        uint128 liquidityLower,
        uint128 liquidityUpper
    ) internal pure returns (uint256 capital) {
        uint256 capitalLeft;
        {
            (uint256 amount0, uint256 amount1) = tvl(leftLowerTick, leftUpperTick, currentTick, liquidityLower);
            capitalLeft = getCapital(amount0, amount1, currentTick);
        }
        uint256 capitalRight;
        {
            (uint256 amount0, uint256 amount1) = tvl(rightLowerTick, rightUpperTick, currentTick, liquidityUpper);
            capitalRight = getCapital(amount0, amount1, currentTick);
        }
        return capitalRight + capitalLeft;
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

        console2.log("Before withdrawal");
        console2.log("Balance: ", wethContract.balanceOf(deployer));
        console2.log("Small amount: ", smallAmount);
        console2.log("Weth balance: ", address(wethContract).balance);
        wethContract.withdraw(smallAmount / 2);
        console2.log("Before exchange");
        curvePool.exchange{value: smallAmount / 2}(0, 1, smallAmount / 2, 0);
        console2.log("After exchange");
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

    function preparePush(
        IUniV3Vault vault,
        int24 tickLower,
        int24 tickUpper
    ) public {
        vm.startPrank(admin);
        IVaultRegistry(registry).approve(deployer, vault.nft());
        vm.stopPrank();

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
            uint8[] memory args = new uint8[](1);
            args[0] = PermissionIdsLibrary.ERC20_VAULT_TOKEN;
            vm.prank(admin);
            protocolGovernance.stagePermissionGrants(wsteth, args);
        }

        vm.warp(block.timestamp + protocolGovernance.governanceDelay());
        vm.prank(admin);
        protocolGovernance.commitPermissionGrants(wsteth);

        console2.log("Commited grants");

        address[] memory tokens = new address[](2);
        tokens[0] = wsteth;
        tokens[1] = weth;

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);

        uint256 uniV3LowerVaultNft = vaultRegistry.vaultsCount() + 1;

        vm.startPrank(admin);

        {
            IUniV3VaultGovernance uniV3VaultGovernance = IUniV3VaultGovernance(uniGovernance);
            console2.log("Before create");
            uniV3VaultGovernance.createVault(tokens, admin, uint24(uniV3PoolFee), helper);
            uniV3VaultGovernance.createVault(tokens, admin, uint24(uniV3PoolFee), helper);
            console2.log("After create");
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
        return uniV3LowerVaultNft;
    }

    function execute(
        int24 rebalanceTick,
        int24 initialTick,
        int24 shiftedTick
    ) public {
        
    }

    function test() public {
        address stethGovernance = 0x2e59A20f205bB85a89C53f1936454680651E618e;

        vm.startPrank(stethGovernance);
        ISTETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84).removeStakingLimit();
        vm.stopPrank();

        uint256 nft = setup();


    }
}