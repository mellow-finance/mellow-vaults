// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../src/interfaces/external/pancakeswap/ISmartRouter.sol";

import "../../src/strategies/PancakeSwapPulseStrategyV2.sol";

import "../../src/test/MockRouter.sol";

import "../../src/utils/DepositWrapper.sol";
import "../../src/utils/PancakeSwapHelper.sol";
import "../../src/utils/PancakeSwapPulseV2Helper.sol";

import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/vaults/PancakeSwapVault.sol";
import "../../src/vaults/PancakeSwapVaultGovernance.sol";

import "../../src/utils/TestPancakeHelper.sol";

import "../../src/oracles/PancakeChainlinkOracle.sol";

contract DeployPancakeVault is Script {
    using SafeERC20 for IERC20;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IPancakeSwapVault public pancakeSwapVault;

    uint256 public nftStart;

    address public protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address public strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public axl = 0x467719aD09025FcC6cF6F8311755809d45a5E5f3;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    IPancakeNonfungiblePositionManager public positionManager =
        IPancakeNonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);
    IMasterChef public masterChef = IMasterChef(0x556B9306565093C855AEA9AE92A594704c2Cd59e);

    address public swapRouter = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;

    address public oneInchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    PancakeSwapVaultGovernance public pancakeSwapVaultGovernance =
        PancakeSwapVaultGovernance(0x99cb0f623B2679A6b83e0576950b2A4a55027557);

    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    DepositWrapper public depositWrapper = DepositWrapper(0x231002439E1BD5b610C3d98321EA760002b9Ff64);

    PancakeSwapHelper public vaultHelper;

    uint256 public constant Q96 = 2 ** 96;

    function firstDeposit(address strategy) public {
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 10 ** 6;
        tokenAmounts[1] = 10 ** 6;

        if (IERC20(usdc).allowance(msg.sender, address(depositWrapper)) == 0) {
            IERC20(usdc).safeIncreaseAllowance(address(depositWrapper), type(uint128).max);
        }

        if (IERC20(axl).allowance(msg.sender, address(depositWrapper)) == 0) {
            IERC20(axl).safeApprove(address(depositWrapper), type(uint256).max);
        }

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
    }

    function combineVaults(address strategy_, address[] memory tokens, uint256[] memory nfts) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        uint256 nft;
        (rootVault, nft) = rootVaultGovernance.createVault(tokens, address(strategy_), nfts, deployer);
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
                privateVault: true,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        address[] memory wl = new address[](1);
        wl[0] = address(depositWrapper);
        rootVault.addDepositorsToAllowlist(wl);

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function deployVaults(address strategy) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = axl;
        tokens[1] = usdc;
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IPancakeSwapVaultGovernance(pancakeSwapVaultGovernance).createVault(
            tokens,
            deployer,
            2500,
            address(vaultHelper),
            address(masterChef),
            address(erc20Vault)
        );

        pancakeSwapVault = IPancakeSwapVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        pancakeSwapVaultGovernance.setStrategyParams(
            pancakeSwapVault.nft(),
            IPancakeSwapVaultGovernance.StrategyParams({
                swapSlippageD: 1e7,
                poolForSwap: 0x11A6713B702817DB0Aa0964D1AfEe4E641319732,
                cake: 0x152649eA73beAb28c5b49B26eb48f7EAD6d4c898,
                underlyingToken: usdc,
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
            combineVaults(address(strategy), tokens, nfts);
        }
    }

    function deployGovernances() public {
        pancakeSwapVaultGovernance = PancakeSwapVaultGovernance(0x99cb0f623B2679A6b83e0576950b2A4a55027557);
    }

    function initializeStrategy(PancakeSwapPulseStrategyV2 strategy) public {
        strategy.initialize(
            PancakeSwapPulseStrategyV2.ImmutableParams({
                erc20Vault: erc20Vault,
                pancakeSwapVault: pancakeSwapVault,
                router: address(oneInchRouter),
                tokens: erc20Vault.vaultTokens()
            }),
            operator
        );

        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e7;
        minSwapAmounts[1] = 1e7;

        strategy.updateMutableParams(
            PancakeSwapPulseStrategyV2.MutableParams({
                priceImpactD6: 0,
                defaultIntervalWidth: 4200,
                maxPositionLengthInTicks: 10000,
                maxDeviationForVaultPool: 100,
                timespanForAverageTick: 30,
                neighborhoodFactorD: 150000000,
                extensionFactorD: 2000000000,
                swapSlippageD: 1e7,
                swappingAmountsCoefficientD: 1e7,
                minSwapAmounts: minSwapAmounts
            })
        );

        strategy.updateDesiredAmounts(
            PancakeSwapPulseStrategyV2.DesiredAmounts({amount0Desired: 1e6, amount1Desired: 1e6})
        );
    }

    PancakeSwapPulseStrategyV2 public baseStrategy =
        PancakeSwapPulseStrategyV2(0xC68a8c6A29412827018A23058E0CEd132889Ea48);
    PancakeSwapPulseV2Helper public strategyHelper =
        PancakeSwapPulseV2Helper(0x8bc60087Ca542511De2F6865E4257775cf2B5ca8);

    // deploy
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        // PancakeChainlinkOracle oc = new PancakeChainlinkOracle(
        //     axl,
        //     usdc,
        //     2500,
        //     positionManager
        // );

        // console2.log(oc.description(), oc.latestAnswer());

        // TransparentUpgradeableProxy newStrategy = new TransparentUpgradeableProxy(
        //     address(baseStrategy),
        //     deployer,
        //     new bytes(0)
        // );

        // vaultHelper = new PancakeSwapHelper(positionManager);

        // deployVaults(address(newStrategy));
        // firstDeposit(address(newStrategy));

        // IERC20(axl).safeTransfer(address(newStrategy), 1e7);
        // IERC20(usdc).safeTransfer(address(newStrategy), 1e7);

        // vm.stopBroadcast();
        // vm.startBroadcast(vm.envUint("OPERATOR_PK"));

        // PancakeSwapPulseStrategyV2 strategy = PancakeSwapPulseStrategyV2(address(newStrategy));
        // initializeStrategy(strategy);

        // (uint256 amountIn, address from, address to, IERC20Vault erc20Vault_) = strategyHelper.calculateAmountForSwap(
        //     strategy
        // );

        // console2.log(amountIn, from, to, address(erc20Vault_));

        // strategy.rebalance(type(uint256).max, new bytes(0), 0);

        // vm.stopBroadcast();
        // vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        // depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);

        // uint256[] memory tokenAmounts = new uint256[](2);
        // tokenAmounts[0] = 5e7;
        // tokenAmounts[1] = 5e7;

        // depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));

        vm.stopBroadcast();
    }
}
