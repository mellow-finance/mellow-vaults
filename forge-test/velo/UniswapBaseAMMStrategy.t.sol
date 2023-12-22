// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import "../../src/strategies/BaseAMMStrategy.sol";

import "../../src/test/MockRouter.sol";

import "../../src/utils/DepositWrapper.sol";
import "../../src/utils/UniV3Helper.sol";

import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/vaults/UniV3Vault.sol";
import "../../src/vaults/UniV3VaultGovernance.sol";

import "../../src/adapters/UniswapV3Adapter.sol";

contract UniswapBaseAMMStrategy is Test {
    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault1;
    IUniV3Vault public uniV3Vault2;

    uint256 public nftStart;
    address public sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address public protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address public strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address public admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public uniV3VaultGovernance = 0x9c319DC47cA6c8c5e130d5aEF5B8a40Cce9e877e;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    DepositWrapper public depositWrapper = new DepositWrapper(deployer);
    MockRouter public router = new MockRouter();

    BaseAMMStrategy public strategy = new BaseAMMStrategy();

    uint256 public constant Q96 = 2**96;

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
        vm.startPrank(deployer);
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = usdc;
        tokens[1] = weth;
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IUniV3VaultGovernance(uniV3VaultGovernance).createVault(
            tokens,
            deployer,
            3000,
            0xA995B345d22Db15c9a36Cb6928967AFCFAb84fDb
        );

        uniV3Vault1 = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        IUniV3VaultGovernance(uniV3VaultGovernance).stageDelayedStrategyParams(
            erc20VaultNft + 1,
            IUniV3VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );

        IUniV3VaultGovernance(uniV3VaultGovernance).commitDelayedStrategyParams(erc20VaultNft + 1);
        IUniV3VaultGovernance(uniV3VaultGovernance).createVault(
            tokens,
            deployer,
            3000,
            0xA995B345d22Db15c9a36Cb6928967AFCFAb84fDb
        );

        uniV3Vault2 = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        IUniV3VaultGovernance(uniV3VaultGovernance).stageDelayedStrategyParams(
            erc20VaultNft + 2,
            IUniV3VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );
        IUniV3VaultGovernance(uniV3VaultGovernance).commitDelayedStrategyParams(erc20VaultNft + 2);

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            nfts[2] = erc20VaultNft + 2;
            combineVaults(tokens, nfts);
        }
        vm.stopPrank();
    }

    function deployGlobalParams() public {
        vm.startPrank(admin);
        uint8[] memory permission = new uint8[](2);
        permission[0] = 2;
        permission[0] = 3;
        IProtocolGovernance(governance).stageValidator(address(router), 0xa8a78538Fc6D44951d6e957192a9772AfB02dd2f);
        permission = new uint8[](1);
        permission[0] = 4;
        IProtocolGovernance(governance).stagePermissionGrants(address(router), permission);
        skip(24 * 3600);
        IProtocolGovernance(governance).commitPermissionGrants(address(router));
        IProtocolGovernance(governance).commitValidator(address(router));
        vm.stopPrank();
    }

    function initializeStrategy() public {
        vm.startPrank(sAdmin);

        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e8;
        minSwapAmounts[1] = 1e6;

        IIntegrationVault[] memory ammVaults = new IIntegrationVault[](2);
        ammVaults[0] = uniV3Vault1;
        ammVaults[1] = uniV3Vault2;

        strategy.initialize(
            sAdmin,
            BaseAMMStrategy.ImmutableParams({
                erc20Vault: erc20Vault,
                ammVaults: ammVaults,
                adapter: new UniswapV3Adapter(positionManager),
                pool: address(uniV3Vault1.pool())
            }),
            BaseAMMStrategy.MutableParams({
                securityParams: new bytes(0),
                maxPriceSlippageX96: Q96 / 100,
                maxTickDeviation: 5,
                minCapitalRatioDeviationX96: Q96 / 100,
                minSwapAmounts: new uint256[](2)
            })
        );

        vm.stopPrank();
    }

    function deposit(uint256 coef) public {
        uint256 totalSupply = rootVault.totalSupply();
        uint256[] memory tokenAmounts = rootVault.pullExistentials();
        address[] memory tokens = rootVault.vaultTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] *= 10 * coef;
            deal(tokens[i], deployer, tokenAmounts[i]);
        }
        vm.startPrank(deployer);
        if (totalSupply == 0) {
            for (uint256 i = 0; i < tokens.length; i++) {
                IERC20(tokens[i]).approve(address(depositWrapper), type(uint256).max);
            }
            depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
        } else {
            depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
        }
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));

        vm.stopPrank();
    }

    function simpleRebalance() public {
        // (, int24 lowerTick, , , , , ) = uniV3Vault.pool().slot0();
        // int24 tickSpacing = uniV3Vault.pool().tickSpacing();
        // lowerTick -= lowerTick % tickSpacing;
        // int24 upperTick = lowerTick + 1000 * tickSpacing;
        // lowerTick -= 1000 * tickSpacing;
        // BasePulseStrategy.Interval memory interval = BasePulseStrategy.Interval({
        //     lowerTick: lowerTick,
        //     upperTick: upperTick
        // });
        // (uint256 amountIn, address from, address to, ) = strategyHelper.calculateAmountForSwap(strategy, interval);
        // bytes memory swapData = abi.encodeWithSelector(router.swap.selector, amountIn, from, to, address(erc20Vault));
        // actualizeRouter(from);
        // deal(usdc, address(strategy), 10 ** 6);
        // deal(ohm, address(strategy), 10 ** 6);
        // vm.startPrank(sAdmin);
        // strategy.rebalance(type(uint256).max, interval, swapData, 0);
        // vm.stopPrank();
    }

    function smartRebalance() public {
        // BasePulseStrategy.Interval memory interval = olympusStrategy.calculateInterval();
        // console2.log(
        //     "New interval: -",
        //     uint256(int256(-interval.lowerTick)),
        //     "-",
        //     uint256(-int256(interval.upperTick))
        // );
        // (uint256 amountIn, address from, address to, ) = strategyHelper.calculateAmountForSwap(strategy, interval);
        // bytes memory swapData = abi.encodeWithSelector(router.swap.selector, amountIn, from, to, address(erc20Vault));
        // actualizeRouter(from);
        // vm.startPrank(sAdmin);
        // strategy.grantRole(strategy.ADMIN_DELEGATE_ROLE(), address(sAdmin));
        // strategy.grantRole(strategy.OPERATOR(), address(olympusStrategy));
        // olympusStrategy.rebalance(type(uint256).max, swapData, 0);
        // vm.stopPrank();
    }

    function manualRebalance(int24 lowerTick, int24 upperTick) public {
        // BasePulseStrategy.Interval memory interval = BasePulseStrategy.Interval({
        //     lowerTick: lowerTick,
        //     upperTick: upperTick
        // });
        // (uint256 amountIn, address from, address to, ) = strategyHelper.calculateAmountForSwap(strategy, interval);
        // bytes memory swapData = abi.encodeWithSelector(router.swap.selector, amountIn, from, to, address(erc20Vault));
        // actualizeRouter(from);
        // vm.startPrank(sAdmin);
        // strategy.rebalance(type(uint256).max, interval, swapData, 0);
        // vm.stopPrank();
    }

    function test() external {
        deployGlobalParams();
        deployVaults();
        initializeStrategy();
        deposit(1);
        simpleRebalance();
        deposit(100);
        smartRebalance();
        smartRebalance();
        manualRebalance(-45900, -45000);
        smartRebalance();
    }
}
