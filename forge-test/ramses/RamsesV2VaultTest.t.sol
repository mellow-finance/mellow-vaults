// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "../../src/interfaces/external/ramses/ISwapRouter.sol";

import "../../src/test/MockRouter.sol";

import "../../src/utils/StakingDepositWrapper.sol";
import "../../src/utils/RamsesV2Helper.sol";
import "../../src/utils/GRamsesStrategyHelper.sol";

import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/vaults/RamsesV2Vault.sol";
import "../../src/vaults/RamsesV2VaultGovernance.sol";

import "../../src/strategies/GRamsesStrategy.sol";

contract RamsesV2VaultTest is Test {
    using SafeERC20 for IERC20;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IRamsesV2Vault public lowerVault;
    IRamsesV2Vault public upperVault;

    address public router = 0xAA23611badAFB62D37E7295A682D21960ac85A90;
    address public quoter = 0xAA20EFF7ad2F523590dE6c04918DaAE0904E3b20;

    address public grai = 0x894134a25a5faC1c2C26F1d8fBf05111a3CB9487;
    address public lusd = 0x93b346b6BC2548dA6A1E7d98E9a421B42541425b;

    address public sAdmin = 0x49e99fd160a04304b6CFd251Fce0ACB0A79c626d;
    address public protocolTreasury = 0xDF6780faC92ec8D5f366584c29599eA1c97C77F5;
    address public strategyTreasury = 0xb0426fDFEfF47B23E5c2794D406A3cC8E77Ec001;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public admin = 0x160cda72DEc5E7ECc82E0a98CF13c29B0a2396E4;

    address public governance = 0x65a440a89824AB464d7c94B184eF494c1457258D;
    address public registry = 0x7D7fEF7bF8bE4DB0FFf06346C59efc24EE8e4c22;
    address public rootGovernance = 0xC75825C5539968648632ec6207f8EDeC407dF891;
    address public erc20Governance = 0x7D62E2c0516B8e747d95323Ca350c847C4Dea533;
    address public mellowOracle = 0x3EFf1DA9e5f72d51F268937d3A5426c2bf5eFf4A;

    address public erc20Validator = 0xa3420E55cC602a65bFA114A955DB1B1D4CA03745;
    address public allowAllValidator = 0x4c31e14F344CDD2921995C62F7a15Eea6B9E7521;

    IRamsesV2NonfungiblePositionManager public positionManager =
        IRamsesV2NonfungiblePositionManager(0xAA277CB7914b7e5514946Da92cb9De332Ce610EF);
    RamsesV2VaultGovernance public ramsesGovernance;
    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    StakingDepositWrapper public depositWrapper = new StakingDepositWrapper(deployer);
    RamsesV2Helper public vaultHelper = new RamsesV2Helper(positionManager);

    GRamsesStrategy public strategy = new GRamsesStrategy(positionManager);

    uint256 public constant Q96 = 2**96;
    address[] public rewards;
    RamsesInstantFarm public lpFarm;

    function deposit(bool flag) public {
        deal(lusd, deployer, 100 ether);
        deal(grai, deployer, 100 ether);

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = flag ? 10 ether : 1e15;
        tokenAmounts[1] = flag ? 10 ether : 1e15;

        vm.startPrank(deployer);
        IERC20(lusd).approve(address(depositWrapper), type(uint256).max);
        IERC20(grai).approve(address(depositWrapper), type(uint256).max);

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), flag);
        depositWrapper.deposit(rootVault, lpFarm, tokenAmounts, 0, new bytes(0));

        vm.stopPrank();
    }

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

    function deployVaults() public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = grai;
        tokens[1] = lusd;
        vm.startPrank(deployer);
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        ramsesGovernance.createVault(tokens, deployer, 500, address(vaultHelper), address(erc20Vault));
        lowerVault = IRamsesV2Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));
        ramsesGovernance.stageDelayedStrategyParams(
            lowerVault.nft(),
            IRamsesV2VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );
        ramsesGovernance.commitDelayedStrategyParams(lowerVault.nft());

        ramsesGovernance.createVault(tokens, deployer, 500, address(vaultHelper), address(erc20Vault));
        upperVault = IRamsesV2Vault(vaultRegistry.vaultForNft(erc20VaultNft + 2));
        ramsesGovernance.stageDelayedStrategyParams(
            upperVault.nft(),
            IRamsesV2VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );
        ramsesGovernance.commitDelayedStrategyParams(upperVault.nft());

        {
            uint256[] memory nfts = new uint256[](3);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            nfts[2] = erc20VaultNft + 2;
            combineVaults(tokens, nfts);
        }

        lpFarm = new RamsesInstantFarm(
            RamsesInstantFarm.InitParams({
                lpToken: address(rootVault),
                admin: deployer,
                rewardTokens: rewards,
                xram: xram,
                ram: ram,
                weth: weth,
                router: address(router),
                wethRamPool: 0x688547381eEC7C1d3d9eBa778fE275D1D7e03946,
                wethPool: 0x2Ed095289b2116D7a3399e278D603A4e4015B19D,
                timespan: 60,
                maxTickDeviation: 50
            })
        );
        vm.stopPrank();
    }

    address public ram = 0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418;
    address public xram = 0xAAA1eE8DC1864AE49185C368e8c64Dd780a50Fb7;
    address public weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function deployGovernances() public {
        rewards = new address[](2);
        rewards[0] = ram;
        rewards[1] = xram;

        ramsesGovernance = new RamsesV2VaultGovernance(
            IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: IVaultRegistry(registry),
                singleton: IVault(address(new RamsesV2Vault()))
            }),
            IRamsesV2VaultGovernance.DelayedProtocolParams({
                positionManager: positionManager,
                oracle: IOracle(mellowOracle)
            })
        );

        uint8[] memory tokenPermissions = new uint8[](2);
        tokenPermissions[0] = 2;
        tokenPermissions[1] = 3;

        uint8[] memory routerPermissions = new uint8[](1);
        routerPermissions[0] = 4;

        vm.startPrank(admin);

        IProtocolGovernance(governance).stagePermissionGrants(address(ramsesGovernance), new uint8[](1));
        // IProtocolGovernance(governance).stagePermissionGrants(address(lusd), tokenPermissions);
        // IProtocolGovernance(governance).stagePermissionGrants(address(grai), tokenPermissions);
        // IProtocolGovernance(governance).stagePermissionGrants(address(router), routerPermissions);
        // IProtocolGovernance(governance).stageValidator(address(grai), erc20Validator);
        // IProtocolGovernance(governance).stageValidator(address(lusd), erc20Validator);
        // IProtocolGovernance(governance).stageValidator(address(router), allowAllValidator);
        // IProtocolGovernance(governance).stageUnitPrice(address(grai), 1e18);
        // IProtocolGovernance(governance).stageUnitPrice(address(lusd), 1e18);

        skip(24 * 3600);

        IProtocolGovernance(governance).commitPermissionGrants(address(ramsesGovernance));
        // IProtocolGovernance(governance).commitPermissionGrants(address(lusd));
        // IProtocolGovernance(governance).commitPermissionGrants(address(grai));
        // IProtocolGovernance(governance).commitPermissionGrants(address(router));
        // IProtocolGovernance(governance).commitValidator(address(grai));
        // IProtocolGovernance(governance).commitValidator(address(lusd));
        // IProtocolGovernance(governance).commitValidator(address(router));
        // IProtocolGovernance(governance).commitUnitPrice(address(grai));
        // IProtocolGovernance(governance).commitUnitPrice(address(lusd));

        vm.stopPrank();
    }

    function getPrice(uint256 amountIn, bool dir) public returns (uint160 sqrtPriceX96) {
        try RamsesV2VaultTest(address(this)).swapRevert(amountIn, dir) {} catch (bytes memory res) {
            assembly {
                res := add(res, 0x04)
            }
            string memory tmp = abi.decode(res, (string));
            sqrtPriceX96 = uint160(vm.parseUint(tmp));
        }
    }

    function swapRevert(uint256 amount, bool dir) public {
        uint160 sqrtPriceX96 = swap(amount, dir);
        require(false, vm.toString(sqrtPriceX96));
    }

    function swap(uint256 amount, bool dir) public returns (uint160 sqrtPriceX96) {
        vm.startPrank(deployer);

        address[2] memory tokens = [grai, lusd];
        address tokenIn = dir ? tokens[1] : tokens[0];
        address tokenOut = !dir ? tokens[1] : tokens[0];

        deal(tokenIn, deployer, amount);
        IERC20(tokenIn).safeApprove(address(router), amount);
        ISwapRouter(router).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 500,
                amountIn: amount,
                deadline: type(uint256).max,
                recipient: deployer,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        (sqrtPriceX96, , , , , , ) = lowerVault.pool().slot0();

        vm.stopPrank();
    }

    function calculateAmounts(int24 targetTick) public returns (bool dir, uint256 amountIn) {
        (uint160 spotSqrtPriceX96, , , , , , ) = lowerVault.pool().slot0();
        uint160 targetPriceX96 = TickMath.getSqrtRatioAtTick(targetTick);
        if (targetPriceX96 == spotSqrtPriceX96) return (false, 0);
        dir = spotSqrtPriceX96 < targetPriceX96;
        uint256 left = 1;
        uint256 right = 2e6 ether;
        uint256 mid;
        uint160 lastSrqtPriceX96 = 0;
        while (left <= right) {
            mid = (left + right) >> 1;
            uint160 testSqrtPriceX96 = getPrice(mid, dir);
            lastSrqtPriceX96 = testSqrtPriceX96;
            if ((spotSqrtPriceX96 < targetPriceX96) == (testSqrtPriceX96 < targetPriceX96)) {
                left = mid + 1;
            } else {
                right = mid - 1;
            }
        }
        return (dir, mid);
    }

    function moveTick(int24 targetTick) public {
        while (true) {
            (bool dir, uint256 amount) = calculateAmounts(targetTick);
            if (amount < 1e9) break;
            swap(amount, dir);
        }
        skip(10 * 60);
    }

    function initializeStrategy() public {
        vm.startPrank(operator);

        deal(grai, address(strategy), 1 ether);
        deal(lusd, address(strategy), 1 ether);

        strategy.initialize(
            operator,
            GRamsesStrategy.ImmutableParams({
                fee: 500,
                pool: IRamsesV2Pool(lowerVault.pool()),
                erc20Vault: erc20Vault,
                lowerVault: lowerVault,
                upperVault: upperVault,
                router: router,
                tokens: lowerVault.vaultTokens()
            })
        );

        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e15;
        minSwapAmounts[1] = 1e15;

        strategy.updateMutableParams(
            GRamsesStrategy.MutableParams({
                timespan: 60,
                maxTickDeviation: 10,
                intervalWidth: 10,
                priceImpactD6: 1000, // 1%
                amount0Desired: 10 gwei,
                amount1Desired: 10 gwei,
                maxRatioDeviationX96: uint256(2**96) / 100,
                swapSlippageD: 1e7,
                swappingAmountsCoefficientD: 1e7,
                minSwapAmounts: minSwapAmounts
            })
        );

        strategy.updateVaultFarms(
            IRamsesV2VaultGovernance.StrategyParams({
                farm: address(lpFarm),
                rewards: rewards,
                gaugeV2: address(0x8cfBc79E06A80f5931B3F9FCC4BbDfac91D45A50),
                instantExitFlag: true
            })
        );
        vm.stopPrank();
    }

    function positionToString(uint256 nft) public view returns (string memory s) {
        (, , , , , int24 lowerTick, int24 upperTick, uint128 liquidity, , , , ) = positionManager.positions(nft);
        s = string(
            abi.encodePacked(
                "[",
                vm.toString(lowerTick),
                ", ",
                vm.toString(upperTick),
                "] liq: ",
                vm.toString(liquidity / 1e18)
            )
        );
    }

    function logState() public view {
        string memory lowerPosition = positionToString(lowerVault.positionId());
        string memory upperPosition = positionToString(upperVault.positionId());
        (, int24 spotTick, , , , , ) = lowerVault.pool().slot0();
        console2.log(lowerPosition, upperPosition, "spot tick:", vm.toString(spotTick));
    }

    function prepare() public {
        vm.startPrank(deployer);
        deal(grai, deployer, 1e6 ether);
        deal(lusd, deployer, 1e6 ether);

        IERC20(grai).safeApprove(address(positionManager), type(uint256).max);
        IERC20(lusd).safeApprove(address(positionManager), type(uint256).max);

        positionManager.mint(
            IRamsesV2NonfungiblePositionManager.MintParams({
                token0: grai,
                token1: lusd,
                fee: 500,
                tickLower: -1000,
                tickUpper: 1000,
                amount0Desired: 1e6 ether,
                amount1Desired: 1e6 ether,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: type(uint256).max
            })
        );

        IERC20(grai).safeApprove(address(positionManager), 0);
        IERC20(lusd).safeApprove(address(positionManager), 0);
        vm.stopPrank();
    }

    uint256 rebalanceIndex = 0;

    GRamsesStrategyHelper public strategyHelper = new GRamsesStrategyHelper();

    function rebalance() public {
        vm.startPrank(operator);
        bytes memory swapData = "";
        if (rebalanceIndex > 0) {
            ISwapRouter.ExactInputSingleParams memory swapParams = strategyHelper.calculateAmountsForSwap(
                strategy,
                rootVault
            );

            swapData = abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, swapParams);
        }
        rebalanceIndex++;
        strategy.rebalance(swapData, 0, type(uint256).max);
        vm.stopPrank();
    }

    function _test() external {
        prepare();

        deployGovernances();
        deployVaults();
        initializeStrategy();
        deposit(false);
        rebalance();
        deposit(true);
        logState();
        console2.log("------------");

        moveTick(-100);
        logState();
        rebalance();
        logState();
        console2.log("------------");

        moveTick(50);
        logState();
        rebalance();
        logState();
        console2.log("------------");

        moveTick(53);
        logState();
        rebalance();
        logState();
        console2.log("------------");

        moveTick(55);
        logState();
        rebalance();
        logState();
        console2.log("------------");

        moveTick(57);
        logState();
        rebalance();
        logState();
        console2.log("------------");

        moveTick(59);
        logState();
        rebalance();
        logState();
        console2.log("------------");

        console2.log(IERC20(rewards[0]).balanceOf(address(lpFarm)), IERC20(rewards[1]).balanceOf(address(lpFarm)));

        vm.startPrank(deployer);
        lpFarm.updateRewardAmounts();

        lpFarm.withdraw(lpFarm.balanceOf(deployer), deployer);
        rootVault.withdraw(deployer, rootVault.balanceOf(deployer), new uint256[](2), new bytes[](3));

        address tstAddress = address(412343241);
        lpFarm.claim(address(tstAddress));

        console2.log(IERC20(ram).balanceOf(tstAddress), IERC20(xram).balanceOf(tstAddress));

        vm.stopPrank();
    }
}
