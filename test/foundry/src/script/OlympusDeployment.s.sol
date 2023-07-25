// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console2.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import "../../src/strategies/BasePulseStrategy.sol";
import "../../src/strategies/OlympusStrategy.sol";

import "../../src/test/MockRouter.sol";

import "../../src/utils/DepositWrapper.sol";
import "../../src/utils/BasePulseStrategyHelper.sol";
import "../../src/utils/UniV3Helper.sol";

import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/vaults/UniV3Vault.sol";
import "../../src/vaults/UniV3VaultGovernance.sol";

import "../../src/oracles/OHMOracle.sol";

contract OlympusDeployment is Script {
    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault;

    uint256 public nftStart;
    address public protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address public strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;

    address public ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
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

    DepositWrapper public depositWrapper = DepositWrapper(0x231002439E1BD5b610C3d98321EA760002b9Ff64);
    BasePulseStrategy public strategy = BasePulseStrategy(0x0c896de0ED46517C8206b82ff7D7824D30892F14);
    OlympusStrategy public olympusStrategy = OlympusStrategy(0x5Ec09Dc83080A17De87aE0bd22097F360e078cf7);
    BasePulseStrategyHelper public strategyHelper = BasePulseStrategyHelper(0x7c59Aae0Ee2EeEdeC34d235FeAF91A45CcAE2cb5);

    uint256 public constant Q96 = 2 ** 96;

    // function deployContracts() public {
    //     strategy = new BasePulseStrategy(positionManager);
    //     olympusStrategy = new OlympusStrategy(
    //         deployer,
    //         strategy,
    //         IOlympusRange(0xb212D9584cfc56EFf1117F412Fe0bBdc53673954),
    //         60,
    //         9,
    //         6,
    //         18,
    //         true
    //     );
    //     strategyHelper = new BasePulseStrategyHelper();
    // }

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
        tokens[0] = ohm;
        tokens[1] = usdc;
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IUniV3VaultGovernance(uniV3VaultGovernance).createVault(
            tokens,
            deployer,
            3000,
            0xA995B345d22Db15c9a36Cb6928967AFCFAb84fDb
        );

        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        IUniV3VaultGovernance(uniV3VaultGovernance).stageDelayedStrategyParams(
            erc20VaultNft + 1,
            IUniV3VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );
        IUniV3VaultGovernance(uniV3VaultGovernance).commitDelayedStrategyParams(erc20VaultNft + 1);

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }
    }

    function initializeStrategy() public {
        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e8;
        minSwapAmounts[1] = 1e6;

        strategy.initialize(
            BasePulseStrategy.ImmutableParams({
                erc20Vault: erc20Vault,
                uniV3Vault: uniV3Vault,
                router: address(0x1111111254EEB25477B68fb85Ed929f73A960582),
                tokens: erc20Vault.vaultTokens()
            }),
            deployer
        );

        strategy.updateMutableParams(
            BasePulseStrategy.MutableParams({
                priceImpactD6: 0,
                maxDeviationForVaultPool: 50,
                timespanForAverageTick: 60,
                swapSlippageD: 1e7,
                swappingAmountsCoefficientD: 1e7,
                minSwapAmounts: minSwapAmounts
            })
        );

        strategy.updateDesiredAmounts(BasePulseStrategy.DesiredAmounts({amount0Desired: 1e4, amount1Desired: 1e4}));
    }

    function deposit(uint256 coef) public {
        uint256 totalSupply = rootVault.totalSupply();
        uint256[] memory tokenAmounts = rootVault.pullExistentials();
        address[] memory tokens = rootVault.vaultTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] *= 10 * coef;
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

    function smartRebalance() public {
        BasePulseStrategy.Interval memory interval = olympusStrategy.calculateInterval();

        console2.log(
            "New interval: -",
            uint256(int256(-interval.lowerTick)),
            "-",
            uint256(-int256(interval.upperTick))
        );

        // (uint256 amountIn, address from, address to, ) = strategyHelper.calculateAmountForSwap(strategy, interval);

        IERC20(ohm).transfer(address(strategy), 1e4);
        IERC20(usdc).transfer(address(strategy), 1e4);

        strategy.grantRole(strategy.ADMIN_DELEGATE_ROLE(), address(deployer));
        strategy.grantRole(strategy.OPERATOR(), address(olympusStrategy));

        olympusStrategy.rebalance(type(uint256).max, new bytes(0), 0);
    }

    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        OHMOracle oracle = new OHMOracle();

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = oracle
            .latestRoundData();
        console2.log(uint256(answer));

        // deployVaults();
        // initializeStrategy();
        // deposit(1);
        // smartRebalance();
        // deposit(10);

        vm.stopBroadcast();
    }
}
