// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../utils/InstantFarm.sol";
import "../../utils/StakingDepositWrapper.sol";
import "../../utils/PancakeSwapMerklHelper.sol";

import "../../vaults/ERC20Vault.sol";
import "../../vaults/ERC20VaultGovernance.sol";

import "../../vaults/ERC20RootVault.sol";
import "../../vaults/ERC20RootVaultGovernance.sol";

import "../../vaults/PancakeSwapMerklVault.sol";
import "../../vaults/PancakeSwapMerklVaultGovernance.sol";

import "../../strategies/PancakeSwapMerklPulseStrategyV2.sol";

import "./Constants.sol";

contract Deploy is Script {
    using SafeERC20 for IERC20;

    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CAKE = 0x152649eA73beAb28c5b49B26eb48f7EAD6d4c898;
    address public constant RPL = 0xD33526068D116cE69F19A9ee46F0bd304F21A51f;

    address public sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address public protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address public strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;

    address public inchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    IPancakeNonfungiblePositionManager public immutable positionManager =
        IPancakeNonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);

    IPancakeSwapMerklVaultGovernance public pancakeGovernance =
        IPancakeSwapMerklVaultGovernance(0x459d212ED6821d2A90d64a44673F239e5995FB33);
    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);
    PancakeSwapMerklPulseStrategyV2 public baseStrategy =
        PancakeSwapMerklPulseStrategyV2(0x215795f035096320ad1b5E85C80365138BFFe2D0);
    StakingDepositWrapper public depositWrapper = StakingDepositWrapper(0x9B8058Fa941835D5F287680D2f569935356B9730);

    uint256 public constant Q96 = 2**96;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IPancakeSwapMerklVault public pancakeVault;
    InstantFarm public lpFarm;

    TransparentUpgradeableProxy public strategy;

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

    function deployVaults() public {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = RETH;
        tokens[1] = WETH;
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        PancakeSwapMerklHelper vaultHelper = PancakeSwapMerklHelper(0x1C07b3a4E59b75b11FFf1D0cf54E635B043cf04e);

        IPancakeSwapMerklVaultGovernance(pancakeGovernance).createVault(
            tokens,
            deployer,
            500,
            address(vaultHelper),
            address(erc20Vault)
        );

        address[] memory rewards = new address[](2);
        rewards[0] = RPL;
        rewards[1] = CAKE;

        pancakeVault = IPancakeSwapMerklVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));
        pancakeGovernance.stageDelayedStrategyParams(
            erc20VaultNft + 1,
            IPancakeSwapMerklVaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );

        pancakeGovernance.commitDelayedStrategyParams(erc20VaultNft + 1);

        strategy = new TransparentUpgradeableProxy(address(baseStrategy), deployer, new bytes(0));
        IERC20(RETH).safeTransfer(address(strategy), 1e10);
        IERC20(WETH).safeTransfer(address(strategy), 1e10);

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        lpFarm = new InstantFarm(address(rootVault), deployer, rewards);
        vm.stopBroadcast();
    }

    function initStrategy() public {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("OPERATOR_PK"))));
        PancakeSwapMerklPulseStrategyV2(address(strategy)).initialize(
            PancakeSwapMerklPulseStrategyV2.ImmutableParams({
                erc20Vault: erc20Vault,
                pancakeSwapVault: pancakeVault,
                router: inchRouter,
                tokens: erc20Vault.vaultTokens()
            }),
            operator
        );

        PancakeSwapMerklPulseStrategyV2(address(strategy)).updateFarms(
            address(lpFarm),
            address(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae)
        );
        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e15;
        minSwapAmounts[1] = 1e15;

        PancakeSwapMerklPulseStrategyV2(address(strategy)).updateMutableParams(
            PancakeSwapMerklPulseStrategyV2.MutableParams({
                priceImpactD6: 0,
                defaultIntervalWidth: 20,
                maxPositionLengthInTicks: 120,
                maxDeviationForVaultPool: 5,
                timespanForAverageTick: 30,
                neighborhoodFactorD: 150000000,
                extensionFactorD: 2000000000,
                swapSlippageD: 10000000,
                swappingAmountsCoefficientD: 10000000,
                minSwapAmounts: minSwapAmounts
            })
        );
        PancakeSwapMerklPulseStrategyV2(address(strategy)).updateDesiredAmounts(
            PancakeSwapMerklPulseStrategyV2.DesiredAmounts({amount0Desired: 1e9, amount1Desired: 1e9})
        );
        PancakeSwapMerklPulseStrategyV2(address(strategy)).rebalance(type(uint256).max, "", 0);
        vm.stopBroadcast();
    }

    function firstDeposit() public {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));
        depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
        IERC20(RETH).safeApprove(address(depositWrapper), type(uint256).max);
        IERC20(WETH).safeApprove(address(depositWrapper), type(uint256).max);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e11;
        amounts[1] = 1e11;
        depositWrapper.deposit(rootVault, lpFarm, amounts, 0, "");
        vm.stopBroadcast();
    }

    function deposit() public {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 4e16;
        amounts[1] = 4e16;
        depositWrapper.deposit(rootVault, lpFarm, amounts, 0, "");
        vm.stopBroadcast();
    }

    uint256 public constant LENGTH = 10;

    function run() external {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));

        address[] memory tokens = new address[](2);
        tokens[0] = 0x152649eA73beAb28c5b49B26eb48f7EAD6d4c898;
        tokens[1] = 0xD33526068D116cE69F19A9ee46F0bd304F21A51f;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 119164795500000000;
        amounts[1] = 15160655400000000;

        bytes32[10][2] memory staticProofs = [
            [
                bytes32(0xdbe66cb2182a645b72ceac7b91747d7b6d9977818e1220fed99c212f6578aa70),
                bytes32(0x6c0c6c408df91549a5ef5201eeccb1eec57767dee6cc52cf208f1a95cc7715ea),
                bytes32(0xa00afda21edd5cd78d3565b8a4da081275aac143cbb5465706151084fe28f400),
                bytes32(0x9854c8db6adcbad6f10ed39e7e3f238c0d502ac68f2a421b7e396839b3167928),
                bytes32(0x80e5b3b55d92c049908e9bff08ec8a8346de863f0c952847102f0f57d70e00fd),
                bytes32(0xbbbc6781e9db4b17497e4eda7d5e2891db9931bd73d4cd448519b49a66e6bab6),
                bytes32(0x5df38f08da2cc30542ee38e926a62933fec3893a203ea1956d21c357da312abb),
                bytes32(0x388352d252f9a6add226375a19654f048e3b19875ab7909c3084ca3593b0314d),
                bytes32(0xadfb2ef6ff567c0b57b7a53cde8e1a48f96929310f3fc3784967aeb533f0f9f0),
                bytes32(0x4e452adfedd76a5b4074d03ecf0e0c25e6d4e65bb8465d73bfa24c7dfaefde72)
            ],
            [
                bytes32(0xa6e705f0246ca0c35f226fd859eb36e9cdf60d2f29f3ef44d00f03906c8486d1),
                bytes32(0x6c0c6c408df91549a5ef5201eeccb1eec57767dee6cc52cf208f1a95cc7715ea),
                bytes32(0xa00afda21edd5cd78d3565b8a4da081275aac143cbb5465706151084fe28f400),
                bytes32(0x9854c8db6adcbad6f10ed39e7e3f238c0d502ac68f2a421b7e396839b3167928),
                bytes32(0x80e5b3b55d92c049908e9bff08ec8a8346de863f0c952847102f0f57d70e00fd),
                bytes32(0xbbbc6781e9db4b17497e4eda7d5e2891db9931bd73d4cd448519b49a66e6bab6),
                bytes32(0x5df38f08da2cc30542ee38e926a62933fec3893a203ea1956d21c357da312abb),
                bytes32(0x388352d252f9a6add226375a19654f048e3b19875ab7909c3084ca3593b0314d),
                bytes32(0xadfb2ef6ff567c0b57b7a53cde8e1a48f96929310f3fc3784967aeb533f0f9f0),
                bytes32(0x4e452adfedd76a5b4074d03ecf0e0c25e6d4e65bb8465d73bfa24c7dfaefde72)
            ]
        ];
        bytes32[][] memory proofs = new bytes32[][](2);
        for (uint256 i = 0; i < 2; i++) {
            proofs[i] = new bytes32[](10);
            for (uint256 j = 0; j < 10; j++) {
                proofs[i][j] = staticProofs[i][j];
            }
        }

        PancakeSwapMerklVault(0x882a41Fd4C5d09D01900DB378903C5C00Cc31D64).compound(tokens, amounts, proofs);

        InstantFarm(0x7051126223a559E3500bd0843924d971f55F0533).updateRewardAmounts();

        vm.stopBroadcast();
    }
}
