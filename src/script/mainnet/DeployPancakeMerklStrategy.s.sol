// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
    StakingDepositWrapper public depositWrapper;

    uint256 public constant Q96 = 2**96;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IPancakeSwapMerklVault public pancakeVault;
    InstantFarm public lpFarm;

    PancakeSwapMerklPulseStrategyV2 public strategy;

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
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = RETH;
        tokens[1] = WETH;
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        PancakeSwapMerklHelper vaultHelper = new PancakeSwapMerklHelper(positionManager);

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

        strategy = new PancakeSwapMerklPulseStrategyV2(positionManager);
        strategy.initialize(
            PancakeSwapMerklPulseStrategyV2.ImmutableParams({
                erc20Vault: erc20Vault,
                pancakeSwapVault: pancakeVault,
                router: inchRouter,
                tokens: erc20Vault.vaultTokens()
            }),
            operator
        );

        IERC20(RETH).safeTransfer(address(strategy), 1e10);
        IERC20(WETH).safeTransfer(address(strategy), 1e10);

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        lpFarm = new InstantFarm(address(rootVault), deployer, rewards);
    }

    function run() external {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));
        PancakeSwapMerklVault singleton = new PancakeSwapMerklVault();

        // pancakeGovernance = new PancakeSwapMerklVaultGovernance(
        //     IVaultGovernance.InternalParams({
        //         protocolGovernance: IProtocolGovernance(governance),
        //         registry: IVaultRegistry(registry),
        //         singleton: IVault(address(singleton))
        //     }),
        //     IPancakeSwapMerklVaultGovernance.DelayedProtocolParams({
        //         positionManager: positionManager,
        //         oracle: IOracle(mellowOracle)
        //     })
        // );

        // address[] memory tokens = new address[](2);
        // tokens[0] = CAKE;
        // tokens[1] = RPL;
        // uint256[] memory amounts = new uint256[](2);
        // amounts[0] = 3088773800000000;
        // amounts[1] = 333247100000000;
        // bytes32[][] memory proofs = new bytes32[][](2);

        // proofs[0] = new bytes32[](12);

        // bytes32[12] memory firstProof = [
        //     bytes32(0x28ff72d382cd72f5c252000adf1ffe4046a92d1d5ead5a0e55d83401e0744c12),
        //     0x008a180c2b1805c92e5617456d398afdc55ca4d4e631f064500bcfc7fd189e79,
        //     0xc37010c0ba9299a14f3e4b25f2eaf28ef5e32eb1953aca1ff09bf80c02661210,
        //     0xda318b5fdee9dcd2d8a5d7c45d44458a793d0ec288e5ea9b1f14e68a1098af4c,
        //     0x8eb29ee7cd7d49ea2ef60206c59048e8d8d6e7e888878333c696f3c7aaa69e81,
        //     0xdab8f41612f7e0bbc36e0d2a4e1fe6f77b7f844043f298ff677daad518a9ab24,
        //     0xf1947b93d92f19ef3dc6b7a1f63d96537d82fc453b6d715911c60680c79c273f,
        //     0x74c8115c3bab0c0151811dde7d6db1a60ee3e5168852f309f087f6f04becef9f,
        //     0xfce7bac766fa30b12f388f76de92f2c6ff7632c62de9591d9192abbcc0f45fac,
        //     0x1ab78012b889895bf857b359a12ce6e4dd22bb082aebb39f618e89d230e7349d,
        //     0x9da6e0c2a0faad884b77d194bd3cdb859bffcb7763d1746759144be9c9f663f8,
        //     0x29e6427638d8058cd439a21a0b443d0e82d5f856653acf6307e02e1e55614725
        // ];

        // proofs[1] = new bytes32[](12);

        // bytes32[12] memory secondProof = [
        //     bytes32(0x90c4181b8c333ab5da5160bad244461ab1efbdfa6ad2ea507e8392699389c66b),
        //     0xefa3e7f7f84733e11d727cad223a93b4badcbdc29d419688170b03b9f59121b3,
        //     0x093ed64c31071229baeec51cbe0a3fccaed23011c8c06a300aa31d2801099535,
        //     0xda318b5fdee9dcd2d8a5d7c45d44458a793d0ec288e5ea9b1f14e68a1098af4c,
        //     0x8eb29ee7cd7d49ea2ef60206c59048e8d8d6e7e888878333c696f3c7aaa69e81,
        //     0xdab8f41612f7e0bbc36e0d2a4e1fe6f77b7f844043f298ff677daad518a9ab24,
        //     0xf1947b93d92f19ef3dc6b7a1f63d96537d82fc453b6d715911c60680c79c273f,
        //     0x74c8115c3bab0c0151811dde7d6db1a60ee3e5168852f309f087f6f04becef9f,
        //     0xfce7bac766fa30b12f388f76de92f2c6ff7632c62de9591d9192abbcc0f45fac,
        //     0x1ab78012b889895bf857b359a12ce6e4dd22bb082aebb39f618e89d230e7349d,
        //     0x9da6e0c2a0faad884b77d194bd3cdb859bffcb7763d1746759144be9c9f663f8,
        //     0x29e6427638d8058cd439a21a0b443d0e82d5f856653acf6307e02e1e55614725
        // ];

        // console2.log("Here");

        // for (uint256 i = 0; i < 12; i++) {
        //     proofs[0][i] = firstProof[i];
        //     proofs[1][i] = secondProof[i];
        // }

        // PancakeSwapMerklVault(0x6c19E8A70B65053403c9f33d3C858A363EE1E69F).compound(
        //     tokens,
        //     amounts,
        //     proofs
        // );

        // depositWrapper = StakingDepositWrapper(0x9B8058Fa941835D5F287680D2f569935356B9730);

        // rootVault = ERC20RootVault(0xBb467dBD7FA76f0e214eD3cbc32e7606ED2256Fa);

        // lpFarm = InstantFarm(0xc2b4e7C0e3a38b1E41c65747eFC7FAA52Aa0E4D2);

        // uint256[] memory amounts = new uint256[](2);
        // amounts[0] = 1e16;
        // amounts[1] = 1e16;

        // depositWrapper.deposit(rootVault, lpFarm, amounts, 0, "");

        // deployVaults();
        // depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
        // IERC20(RETH).safeApprove(address(depositWrapper), type(uint256).max);
        // IERC20(WETH).safeApprove(address(depositWrapper), type(uint256).max);
        // uint256[] memory amounts = new uint256[](2);
        // amounts[0] = 1e11;
        // amounts[1] = 1e11;
        // depositWrapper.deposit(rootVault, lpFarm, amounts, 0, "");
        // vm.stopBroadcast();

        // vm.startBroadcast(uint256(bytes32(vm.envBytes("OPERATOR_PK"))));
        // strategy.updateFarms(address(lpFarm), address(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae));
        // uint256[] memory minSwapAmounts = new uint256[](2);
        // minSwapAmounts[0] = 1e15;
        // minSwapAmounts[1] = 1e15;
        // strategy.updateMutableParams(
        //     PancakeSwapMerklPulseStrategyV2.MutableParams({
        //         priceImpactD6: 0,
        //         defaultIntervalWidth: 20,
        //         maxPositionLengthInTicks: 120,
        //         maxDeviationForVaultPool: 5,
        //         timespanForAverageTick: 30,
        //         neighborhoodFactorD: 150000000,
        //         extensionFactorD: 2000000000,
        //         swapSlippageD: 10000000,
        //         swappingAmountsCoefficientD: 10000000,
        //         minSwapAmounts: minSwapAmounts
        //     })
        // );
        // strategy.updateDesiredAmounts(
        //     PancakeSwapMerklPulseStrategyV2.DesiredAmounts({amount0Desired: 1e9, amount1Desired: 1e9})
        // );
        // strategy.rebalance(type(uint256).max, "", 0);
        // vm.stopBroadcast();

        // vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));
        // amounts[0] = 1e15;
        // amounts[1] = 1e15;
        // depositWrapper.deposit(rootVault, lpFarm, amounts, 0, "");
        vm.stopBroadcast();
    }
}
