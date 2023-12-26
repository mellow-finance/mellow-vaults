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

import "../../src/strategies/PulseOperatorStrategy.sol";

import "../../src/interfaces/external/univ3/ISwapRouter.sol";

contract UniswapBaseAMMStrategy is Test {
    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault1;
    IUniV3Vault public uniV3Vault2;

    uint256 public nftStart;

    address public protocolTreasury = address(bytes20(keccak256("treasury-1")));
    address public strategyTreasury = address(bytes20(keccak256("treasury-2")));
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;

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

    UniV3Helper public uniV3Helper = new UniV3Helper(positionManager);

    DepositWrapper public depositWrapper = new DepositWrapper(deployer);
    BaseAMMStrategy public strategy = new BaseAMMStrategy();

    uint256 public constant Q96 = 2**96;
    uint24 public constant POOL_FEE = 500;

    IUniswapV3Pool public pool;

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
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = usdc;
        tokens[1] = weth;
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IUniV3VaultGovernance(uniV3VaultGovernance).createVault(tokens, deployer, POOL_FEE, address(uniV3Helper));

        uniV3Vault1 = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        IUniV3VaultGovernance(uniV3VaultGovernance).stageDelayedStrategyParams(
            erc20VaultNft + 1,
            IUniV3VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );

        IUniV3VaultGovernance(uniV3VaultGovernance).commitDelayedStrategyParams(erc20VaultNft + 1);
        IUniV3VaultGovernance(uniV3VaultGovernance).createVault(tokens, deployer, POOL_FEE, address(uniV3Helper));

        uniV3Vault2 = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 2));

        IUniV3VaultGovernance(uniV3VaultGovernance).stageDelayedStrategyParams(
            erc20VaultNft + 2,
            IUniV3VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );
        IUniV3VaultGovernance(uniV3VaultGovernance).commitDelayedStrategyParams(erc20VaultNft + 2);

        pool = uniV3Vault1.pool();
        {
            uint256[] memory nfts = new uint256[](3);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            nfts[2] = erc20VaultNft + 2;
            combineVaults(tokens, nfts);
        }
    }

    UniswapV3Adapter public adapter = new UniswapV3Adapter(positionManager);

    function initializeStrategy() public {
        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e6;
        minSwapAmounts[1] = 1e8;

        IIntegrationVault[] memory ammVaults = new IIntegrationVault[](2);
        ammVaults[0] = uniV3Vault1;
        ammVaults[1] = uniV3Vault2;

        strategy.initialize(
            deployer,
            BaseAMMStrategy.ImmutableParams({
                erc20Vault: erc20Vault,
                ammVaults: ammVaults,
                adapter: adapter,
                pool: address(uniV3Vault1.pool())
            }),
            BaseAMMStrategy.MutableParams({
                securityParams: new bytes(0),
                maxPriceSlippageX96: Q96 / 100,
                maxTickDeviation: 5,
                minCapitalRatioDeviationX96: Q96 / 100,
                minSwapAmounts: new uint256[](2),
                maxCapitalRemainderRatioX96: Q96 / 100
            })
        );
    }

    function deposit(uint256 coef) public {
        uint256 totalSupply = rootVault.totalSupply();
        uint256[] memory tokenAmounts = rootVault.pullExistentials();
        address[] memory tokens = rootVault.vaultTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] *= 10 * coef;
            deal(tokens[i], deployer, tokenAmounts[i]);
        }
        if (totalSupply == 0) {
            for (uint256 i = 0; i < tokens.length; i++) {
                IERC20(tokens[i]).approve(address(depositWrapper), type(uint256).max);
            }
            depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
        } else {
            depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
        }
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
    }

    PulseOperatorStrategy public operatorStrategy;

    function initOperatorStrategy() public {
        operatorStrategy = new PulseOperatorStrategy();
        operatorStrategy.initialize(
            PulseOperatorStrategy.ImmutableParams({strategy: strategy, tickSpacing: pool.tickSpacing()}),
            PulseOperatorStrategy.MutableParams({
                intervalWidth: 100,
                maxPositionLengthInTicks: 200,
                extensionFactorD: 1e9,
                neighborhoodFactorD: 1e8
            }),
            deployer
        );
        strategy.grantRole(strategy.ADMIN_DELEGATE_ROLE(), address(deployer));
        strategy.grantRole(strategy.OPERATOR(), address(operatorStrategy));

        deal(usdc, address(strategy), 1e6);
        deal(weth, address(strategy), 1e15);
    }

    function rebalance() public {
        (address tokenIn, uint256 amountIn, address tokenOut, uint256 expectedAmountOut) = operatorStrategy
            .calculateSwapAmounts(address(rootVault));
        uint256 amountOutMin = (expectedAmountOut * 99) / 100;
        bytes memory data = abi.encodeWithSelector(
            ISwapRouter.exactInputSingle.selector,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 500,
                amountIn: amountIn,
                deadline: type(uint256).max,
                recipient: address(erc20Vault),
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );

        console2.log(IERC20Metadata(tokenIn).symbol(), amountIn);

        operatorStrategy.rebalance(
            BaseAMMStrategy.SwapData({
                router: swapRouter,
                data: data,
                tokenInIndex: tokenIn < tokenOut ? 0 : 1,
                amountIn: amountIn,
                amountOutMin: amountOutMin
            })
        );
    }

    function movePriceUSDC() public {
        while (true) {
            uint256 amountIn = 1e6 * 1e6;
            deal(usdc, deployer, amountIn);
            IERC20(usdc).approve(swapRouter, amountIn);
            ISwapRouter(swapRouter).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: usdc,
                    tokenOut: weth,
                    fee: 500,
                    recipient: deployer,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0,
                    deadline: type(uint256).max
                })
            );
            skip(24 * 3600);
            (, bool flag) = operatorStrategy.calculateExpectedPosition();
            if (flag) break;
        }
    }

    function movePriceWETH() public {
        while (true) {
            uint256 amountIn = 500 ether;
            deal(weth, deployer, amountIn);
            IERC20(weth).approve(swapRouter, amountIn);
            ISwapRouter(swapRouter).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: weth,
                    tokenOut: usdc,
                    fee: 500,
                    recipient: deployer,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0,
                    deadline: type(uint256).max
                })
            );
            skip(24 * 3600);
            (, bool flag) = operatorStrategy.calculateExpectedPosition();
            if (flag) break;
        }
    }

    function test() external {
        vm.startPrank(deployer);
        deployVaults();
        initializeStrategy();
        initOperatorStrategy();
        deposit(1);
        rebalance();
        deposit(1e6);
        for (uint256 i = 0; i < 10; i++) {
            movePriceUSDC();
            rebalance();
            deposit(1e7);
        }
        for (uint256 i = 0; i < 10; i++) {
            movePriceWETH();
            rebalance();
            deposit(1e7);
        }
        vm.stopPrank();
    }
}
