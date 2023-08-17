// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "../../../src/interfaces/external/pancakeswap/ISmartRouter.sol";

import "../../../src/strategies/PancakeSwapPulseStrategyV2.sol";

import "../../../src/test/MockRouter.sol";

import "../../../src/utils/DepositWrapper.sol";
import "../../../src/utils/PancakeSwapHelper.sol";
import "../../../src/utils/PancakeSwapPulseV2Helper.sol";

import "../../../src/vaults/ERC20Vault.sol";
import "../../../src/vaults/ERC20VaultGovernance.sol";

import "../../../src/vaults/ERC20RetroRootVault.sol";
import "../../../src/vaults/ERC20RetroRootVaultGovernance.sol";

import "../../../src/vaults/PancakeSwapVault.sol";
import "../../../src/vaults/PancakeSwapVaultGovernance.sol";

contract PancakePulseV2Test is Test {
    IERC20RetroRootVault public rootVault;
    IERC20Vault public erc20Vault;
    IPancakeSwapVault public pancakeSwapVault;

    uint256 public nftStart;
    address public sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address public protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address public strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address public admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;

    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    IPancakeNonfungiblePositionManager public positionManager =
        IPancakeNonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);
    IMasterChef public masterChef = IMasterChef(0x556B9306565093C855AEA9AE92A594704c2Cd59e);

    address public swapRouter = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;

    PancakeSwapVaultGovernance public pancakeSwapVaultGovernance =
        PancakeSwapVaultGovernance(0x99cb0f623B2679A6b83e0576950b2A4a55027557);
    IERC20RetroRootVaultGovernance public retroRootVaultGovernance;

    PancakeSwapPulseStrategyV2 public strategy = new PancakeSwapPulseStrategyV2(positionManager);
    DepositWrapper public depositWrapper = new DepositWrapper(deployer);
    MockRouter public router = new MockRouter();

    PancakeSwapPulseV2Helper public strategyHelper = new PancakeSwapPulseV2Helper();
    PancakeSwapHelper public vaultHelper = new PancakeSwapHelper(positionManager);

    uint256 public constant Q96 = 2**96;

    function firstDeposit() public {
        deal(usdc, deployer, 10**4);
        deal(weth, deployer, 10**13);

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 10**4;
        tokenAmounts[1] = 10**13;

        vm.startPrank(deployer);
        IERC20(usdc).approve(address(depositWrapper), type(uint256).max);
        IERC20(weth).approve(address(depositWrapper), type(uint256).max);

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);

        depositWrapper.deposit(IERC20RootVault(address(rootVault)), tokenAmounts, 0, new bytes(0));

        vm.stopPrank();
    }

    function deposit() public {
        deal(usdc, deployer, 10**10);
        deal(weth, deployer, 10**19);

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 10**10;
        tokenAmounts[1] = 10**19;

        vm.startPrank(deployer);
        (, bool needToCallCallback) = depositWrapper.depositInfo(address(rootVault));
        if (!needToCallCallback) {
            depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
        }

        depositWrapper.deposit(IERC20RootVault(address(rootVault)), tokenAmounts, 0, new bytes(0));
        vm.stopPrank();
    }

    function withdraw() public {
        vm.startPrank(deployer);
        uint256 lpAmount = rootVault.balanceOf(deployer) / 2;
        rootVault.withdraw(deployer, lpAmount, new uint256[](2), new bytes[](2));
        vm.stopPrank();
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(retroRootVaultGovernance), nfts[i]);
        }

        uint256 nft;
        (rootVault, nft) = retroRootVaultGovernance.createVault(tokens, address(strategy), nfts, deployer);
        retroRootVaultGovernance.setStrategyParams(
            nft,
            IERC20RetroRootVaultGovernance.StrategyParams({
                tokenLimitPerAddress: type(uint256).max,
                tokenLimit: type(uint256).max
            })
        );

        retroRootVaultGovernance.stageDelayedStrategyParams(
            nft,
            IERC20RetroRootVaultGovernance.DelayedStrategyParams({
                strategyTreasury: strategyTreasury,
                strategyPerformanceTreasury: protocolTreasury,
                managementFee: 0,
                performanceFee: 0,
                privateVault: false,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        retroRootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function deployVaults() public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = usdc;
        tokens[1] = weth;
        vm.startPrank(deployer);
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IPancakeSwapVaultGovernance(pancakeSwapVaultGovernance).createVault(
            tokens,
            deployer,
            500,
            address(vaultHelper),
            address(masterChef),
            address(erc20Vault)
        );

        pancakeSwapVault = IPancakeSwapVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        pancakeSwapVaultGovernance.setStrategyParams(
            pancakeSwapVault.nft(),
            IPancakeSwapVaultGovernance.StrategyParams({
                swapSlippageD: 1e7,
                poolForSwap: 0x517F451b0A9E1b87Dc0Ae98A05Ee033C3310F046,
                cake: 0x152649eA73beAb28c5b49B26eb48f7EAD6d4c898,
                underlyingToken: weth,
                smartRouter: swapRouter,
                averageTickTimespan: 30
            })
        );

        pancakeSwapVaultGovernance.stageDelayedStrategyParams(
            erc20VaultNft + 1,
            IPancakeSwapVaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );

        pancakeSwapVaultGovernance.commitDelayedStrategyParams(erc20VaultNft + 1);

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }
        vm.stopPrank();
    }

    function deployGovernances() public {
        IVaultGovernance.InternalParams memory internalParams = ERC20RetroRootVaultGovernance(
            0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA
        ).internalParams();
        internalParams.singleton = new ERC20RetroRootVault();
        retroRootVaultGovernance = new ERC20RetroRootVaultGovernance(
            internalParams,
            ERC20RetroRootVaultGovernance(0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA).delayedProtocolParams(),
            ERC20RetroRootVaultGovernance(0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA).helper()
        );

        vm.startPrank(admin);
        IProtocolGovernance(governance).stagePermissionGrants(address(retroRootVaultGovernance), new uint8[](1));
        uint8[] memory permission = new uint8[](1);
        permission[0] = 4;
        IProtocolGovernance(governance).stagePermissionGrants(address(router), permission);
        IProtocolGovernance(governance).stageValidator(address(router), 0xa8a78538Fc6D44951d6e957192a9772AfB02dd2f);

        skip(24 * 3600);

        IProtocolGovernance(governance).commitPermissionGrants(address(retroRootVaultGovernance));
        IProtocolGovernance(governance).commitPermissionGrants(address(router));
        IProtocolGovernance(governance).commitValidator(address(router));
        vm.stopPrank();
    }

    function initializeStrategy() public {
        vm.startPrank(sAdmin);

        strategy.initialize(
            PancakeSwapPulseStrategyV2.ImmutableParams({
                erc20Vault: erc20Vault,
                pancakeSwapVault: pancakeSwapVault,
                router: address(router),
                tokens: erc20Vault.vaultTokens()
            }),
            sAdmin
        );

        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e7;
        minSwapAmounts[1] = 5e15;

        strategy.updateMutableParams(
            PancakeSwapPulseStrategyV2.MutableParams({
                priceImpactD6: 0,
                defaultIntervalWidth: 4200,
                maxPositionLengthInTicks: 10000,
                maxDeviationForVaultPool: 100,
                timespanForAverageTick: 30,
                neighborhoodFactorD: 1e9,
                extensionFactorD: 1e8,
                swapSlippageD: 1e7,
                swappingAmountsCoefficientD: 1e7,
                minSwapAmounts: minSwapAmounts
            })
        );

        strategy.updateDesiredAmounts(
            PancakeSwapPulseStrategyV2.DesiredAmounts({amount0Desired: 1e6, amount1Desired: 1e9})
        );

        deal(usdc, address(strategy), 10**8);
        deal(weth, address(strategy), 10**11);

        vm.stopPrank();
    }

    function rebalance() public {
        (uint256 amountIn, address tokenIn, address tokenOut, IERC20Vault reciever) = strategyHelper
            .calculateAmountForSwap(strategy);

        {
            deal(usdc, address(router), type(uint128).max);
            deal(weth, address(router), type(uint128).max);

            (uint160 sqrtPriceX96, , , , , , ) = pancakeSwapVault.pool().slot0();
            uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
            if (tokenIn != usdc) priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);

            router.setPrice(priceX96);
        }

        bytes memory swapData = abi.encodeWithSelector(router.swap.selector, amountIn, tokenIn, tokenOut, reciever);

        vm.startPrank(sAdmin);
        strategy.rebalance(type(uint256).max, swapData, 0);
        vm.stopPrank();
    }

    function movePrice(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public {
        vm.startPrank(deployer);
        deal(tokenIn, deployer, amountIn);
        IERC20(tokenIn).approve(swapRouter, amountIn);
        ISmartRouter(swapRouter).exactInputSingle(
            ISmartRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 500,
                recipient: deployer,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        skip(24 * 3600);
        vm.stopPrank();
    }

    function testCompound() external {
        deployGovernances();
        deployVaults();
        firstDeposit();
        initializeStrategy();
        rebalance();

        deposit();

        movePrice(usdc, weth, 1e6 * 100000);
        skip(60 * 60);
        movePrice(usdc, weth, 1e6 * 100000);
        skip(60 * 60);
        movePrice(weth, usdc, 1e18 * 100);

        deposit();

        uint256 calculatedRewards = vaultHelper.calculateActualPendingCake(
            pancakeSwapVault.masterChef(),
            pancakeSwapVault.uniV3Nft()
        );
        uint256 actualRewards = pancakeSwapVault.compound();

        console2.log(calculatedRewards, actualRewards);
        console2.log("retro vault pool: ", rootVault.pool());
    }
}
