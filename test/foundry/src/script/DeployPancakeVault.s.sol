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

    address public protocolTreasury = 0xB39d6DDBa0131bCe0F3ffCE8e8fC777C3A4040c3;
    address public strategyTreasury = 0x458140e51ceb854a341D5de9FA30f6855b78B1b8;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public usdc = 0xA8CE8aee21bC2A48a5EF670afCc9274C7bbbC035;
    address public weth = 0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9;

    address public governance = 0xCD8237f2b332e482DaEaA609D9664b739e93097d;
    address public registry = 0xc02a7B4658861108f9837007b2DF2007d6977116;
    address public rootGovernance = 0x12ED6474A19f24e3a635E312d85fbAc177D66670;
    address public erc20Governance = 0x15b1bC5DF5C44F469394D295959bBEC861893F09;
    address public mellowOracle = 0x286CFBC4798Cf12a61cc57046c4eA0BCACaFDeBb;

    IPancakeNonfungiblePositionManager public positionManager =
        IPancakeNonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);
    IMasterChef public masterChef = IMasterChef(0xE9c7f3196Ab8C09F6616365E8873DaEb207C0391);

    address public swapRouter = 0x678Aa4bF4E210cf2166753e054d5b7c31cc7fa86;
    address public oneInchRouter = 0x678Aa4bF4E210cf2166753e054d5b7c31cc7fa86;

    PancakeSwapVaultGovernance public pancakeSwapVaultGovernance =
        PancakeSwapVaultGovernance(0x070D1CE4eEFd798107A1C4f30b2c47375f3e5dc9);
    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);
    DepositWrapper public depositWrapper;
    PancakeSwapHelper public vaultHelper;

    uint256 public constant Q96 = 2 ** 96;

    function firstDeposit(address strategy) public {
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 10 ** 13;
        tokenAmounts[1] = 10 ** 4;

        if (IERC20(usdc).allowance(msg.sender, address(depositWrapper)) == 0) {
            IERC20(usdc).safeApprove(address(depositWrapper), type(uint128).max);
        }

        if (IERC20(weth).allowance(msg.sender, address(depositWrapper)) == 0) {
            IERC20(weth).safeApprove(address(depositWrapper), type(uint256).max);
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
        tokens[0] = weth;
        tokens[1] = usdc;
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
                swapSlippageD: 1e8,
                poolForSwap: 0xb4BAB40e5a869eF1b5ff440a170A57d9feb228e9,
                cake: 0x0D1E753a25eBda689453309112904807625bEFBe,
                underlyingToken: usdc,
                smartRouter: swapRouter,
                averageTickTimespan: 60
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
        minSwapAmounts[0] = 1e15;
        minSwapAmounts[1] = 1e7;

        strategy.updateMutableParams(
            PancakeSwapPulseStrategyV2.MutableParams({
                priceImpactD6: 0,
                defaultIntervalWidth: 4200,
                maxPositionLengthInTicks: 10000,
                maxDeviationForVaultPool: 50,
                timespanForAverageTick: 30,
                neighborhoodFactorD: 150000000,
                extensionFactorD: 2000000000,
                swapSlippageD: 1e7,
                swappingAmountsCoefficientD: 1e7,
                minSwapAmounts: minSwapAmounts
            })
        );

        strategy.updateDesiredAmounts(
            PancakeSwapPulseStrategyV2.DesiredAmounts({amount0Desired: 1e9, amount1Desired: 1e5})
        );
    }

    PancakeSwapPulseStrategyV2 public baseStrategy =
        PancakeSwapPulseStrategyV2(0x25F964E9dbee1B8960B44eD19180811Af675B0DD);
    TestPancakeHelper public strategyHelper = TestPancakeHelper(0x9a4eDFe062E27058803eEF406EE224bC67224913);

    // deploy
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        vaultHelper = PancakeSwapHelper(0x0d4B508ed0C80de789d49AC36421C2F18a449B24);
        depositWrapper = DepositWrapper(0x67366cc5697d4837fD93EE4beb91EDe75bCec09D);

        TransparentUpgradeableProxy newStrategy = new TransparentUpgradeableProxy(
            address(baseStrategy),
            deployer,
            new bytes(0)
        );

        deployVaults(address(newStrategy));
        firstDeposit(address(newStrategy));

        IERC20(weth).safeTransfer(address(newStrategy), 1e10);
        IERC20(usdc).safeTransfer(address(newStrategy), 1e6);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("OPERATOR_PK"));

        PancakeSwapPulseStrategyV2 strategy = PancakeSwapPulseStrategyV2(address(newStrategy));
        initializeStrategy(strategy);

        (bool neededNewInterval, bytes memory swapData) = strategyHelper.calculateAmountForSwap(strategy);

        strategy.rebalance(type(uint256).max, swapData, 0);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 1e15;
        tokenAmounts[1] = 1e6;

        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));

        vm.stopBroadcast();
    }
}
