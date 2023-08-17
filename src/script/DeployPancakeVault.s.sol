// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

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

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

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
    PancakeSwapHelper public vaultHelper = PancakeSwapHelper(0x6DFd0eb105511615629D2C0B72E1AE4d068346Bc);

    uint256 public constant Q96 = 2**96;

    function firstDeposit(address strategy) public {
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[1] = 10**4;
        tokenAmounts[0] = 10**13;

        // if (IERC20(usdt).allowance(msg.sender, address(depositWrapper)) == 0) {
        //     IERC20(usdt).safeIncreaseAllowance(address(depositWrapper), type(uint128).max);
        // }

        // if (IERC20(weth).allowance(msg.sender, address(depositWrapper)) == 0) {
        IERC20(weth).safeApprove(address(depositWrapper), type(uint256).max);
        // }

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
    }

    function combineVaults(
        address strategy_,
        address[] memory tokens,
        uint256[] memory nfts
    ) public {
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
                privateVault: false,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function deployVaults(address strategy) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[1] = usdt;
        tokens[0] = weth;
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
        minSwapAmounts[1] = 1e7;
        minSwapAmounts[0] = 5e15;

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
    }

    PancakeSwapPulseStrategyV2 public baseStrategy =
        PancakeSwapPulseStrategyV2(0xC68a8c6A29412827018A23058E0CEd132889Ea48);
    PancakeSwapPulseV2Helper public strategyHelper =
        PancakeSwapPulseV2Helper(0x8bc60087Ca542511De2F6865E4257775cf2B5ca8);

    // deploy
    function _run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        TransparentUpgradeableProxy newStrategy = new TransparentUpgradeableProxy(
            address(baseStrategy),
            deployer,
            new bytes(0)
        );

        deployVaults(address(newStrategy));
        firstDeposit(address(newStrategy));

        IERC20(usdt).safeTransfer(address(newStrategy), 1e6);
        IERC20(weth).safeTransfer(address(newStrategy), 1e11);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("OPERATOR_PK"));

        initializeStrategy(PancakeSwapPulseStrategyV2(address(newStrategy)));

        uint256 calculatedRewards = vaultHelper.calculateActualPendingCake(
            pancakeSwapVault.masterChef(),
            pancakeSwapVault.uniV3Nft()
        );
        uint256 actualRewards = pancakeSwapVault.compound();
        console2.log(calculatedRewards, actualRewards);

        vm.stopBroadcast();
    }

    // rebalance
    function run() external {
        vm.startBroadcast(vm.envUint("OPERATOR_PK"));

        bytes
            memory swapData = "0x0502b1c5000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000238b7284ab8000000000000000000000000000000000000000000000000000000000000126d0000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000100000000000000003b6d03403a8414b08ffb128cf1a9da1097b0454e0d4bfa8fcfee7c08";
        PancakeSwapPulseStrategyV2(0xD20f9DBDBc609c591f90c0C8dB3546f150694F84).rebalance(
            type(uint256).max,
            swapData,
            0
        );

        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        depositWrapper.addNewStrategy(
            address(0x74620326155f8Ef1FE4044b18Daf93654521CF9A),
            address(0x1D140852c7a98839E077D640FE0bb7fB1601a229),
            true
        );
        vm.stopBroadcast();
    }
}
