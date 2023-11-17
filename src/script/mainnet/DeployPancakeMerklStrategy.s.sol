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

    function run() external {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));
        address[] memory tokens = new address[](2);
        tokens[0] = 0x152649eA73beAb28c5b49B26eb48f7EAD6d4c898;
        tokens[1] = 0xD33526068D116cE69F19A9ee46F0bd304F21A51f;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 51077119400000000;
        amounts[1] = 6180925800000000;

        bytes32[9][2] memory staticProofs = [
            [
                bytes32(0x4cfad9daf51d3fe3d1813e1a3a14104b7871084cbad5f1d93dd513ded2345487),
                0x1ee51567f5b374077d4f50d6f4a263a6cdcda329e041467b8709a0f3fcc2e59c,
                0x0ae40f70b3f950e01ad0f23534196a7ce8017fb608835db83e36e49e03643817,
                0x2e772913d13a1601705dac2b47f7656815c04fea8015844fae49829a85d54ac6,
                0x8560505f3451b64fe2f7a13c01eb4ffbfc0c71dcd3142df44986bfaa17517097,
                0xb13c53cb22af0ce8d255d4ee13d5bc653492308a0458628085c71a7023106f73,
                0xdd2642db6236554f9382cf6b7ba64e21c9badfe6dc0391b1fddc025d77ca8ab5,
                0xcd4036b42bf499ac2b5c7ad838d3076ed9f497dcf77d80506b13dd47aaf5a23e,
                0xa9cd186f76fccbe1547d9d5e4a91db743dd361960c91cd8976f374b79b16e2f9
            ],
            [
                bytes32(0xac9405a88aa42f3aa325e059f62c21c6743a15106743078f4e2cbd4c8806736b),
                0x08ad0fa949caf91333360e354cbf48db986917e1229dba3c49e3ff379c19b2ef,
                0x0ae40f70b3f950e01ad0f23534196a7ce8017fb608835db83e36e49e03643817,
                0x2e772913d13a1601705dac2b47f7656815c04fea8015844fae49829a85d54ac6,
                0x8560505f3451b64fe2f7a13c01eb4ffbfc0c71dcd3142df44986bfaa17517097,
                0xb13c53cb22af0ce8d255d4ee13d5bc653492308a0458628085c71a7023106f73,
                0xdd2642db6236554f9382cf6b7ba64e21c9badfe6dc0391b1fddc025d77ca8ab5,
                0xcd4036b42bf499ac2b5c7ad838d3076ed9f497dcf77d80506b13dd47aaf5a23e,
                0xa9cd186f76fccbe1547d9d5e4a91db743dd361960c91cd8976f374b79b16e2f9
            ]
        ];
        bytes32[][] memory proofs = new bytes32[][](2);
        for (uint256 i = 0; i < 2; i++) {
            proofs[i] = new bytes32[](9);
            for (uint256 j = 0; j < 9; j++) {
                proofs[i][j] = staticProofs[i][j];
            }
        }

        PancakeSwapMerklVault(0x882a41Fd4C5d09D01900DB378903C5C00Cc31D64).compound(tokens, amounts, proofs);

        InstantFarm(0x7051126223a559E3500bd0843924d971f55F0533).updateRewardAmounts();

        vm.stopBroadcast();
    }
}
