// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "../../src/strategies/BasePulseStrategy.sol";
import "../../src/strategies/OlympusStrategy.sol";

import "../../src/test/MockRouter.sol";

import "../../src/utils/DepositWrapper.sol";
import "../../src/utils/UniV3Helper.sol";

import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/vaults/UniV3Vault.sol";
import "../../src/vaults/UniV3VaultGovernance.sol";

contract OlympusTest is Test {
    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IPancakeSwapVault public pancakeSwapVault;

    uint256 public nftStart;
    address public sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address public protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address public strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address public admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;

    address public ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    INonfungiblePositionManager public positionManager = INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    address public swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    DepositWrapper public depositWrapper = new DepositWrapper(deployer);
    MockRouter public router = new MockRouter();

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
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = usdc;
        tokens[1] = weth;
        vm.startPrank(deployer);
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IUniV3VaultGovernance(pancakeSwapVaultGovernance).createVault(
            tokens,
            deployer,
            500,
            0xe04DC6F116A85508cD6299229218Ed4719E43F2a
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
        vm.startPrank(admin);
        uint8[] memory permission = new uint8[](2);
        permission[0] = 2;
        permission[0] = 3;
        IProtocolGovernance(governance).stagePermissionGrants(address(ohm), permission);
        IProtocolGovernance(governance).stageValidator(address(ohm), 0xf7A19974dC36E1Ad9A74e967B0Bc9B24e0f4C4b3);
        skip(24 * 3600);
        IProtocolGovernance(governance).commitPermissionGrants(address(ohm));
        IProtocolGovernance(governance).commitValidator(address(ohm));
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
    }
}
