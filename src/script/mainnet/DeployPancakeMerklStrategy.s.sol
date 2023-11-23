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
        amounts[0] = 93207241000000000;
        amounts[1] = 11737248600000000;

        bytes32[LENGTH][2] memory staticProofs = [
            [
                bytes32(0x7945c7556831c682a91c8b7e05329a9a18420a823c2fbdab7e868320380e2028),
                bytes32(0x10c4d2d6963432bf7037166289dc81edf8f5ef5a5d822a96d1e93dd1c20c7451),
                bytes32(0x40750d788003fa23e6cd06a37bd33db0ff449796f01dce4d56806b2dec1f508a),
                bytes32(0xf31c01c41fcdbb2032397ad6c316b302a95ba1e96bce48b86d3064d61a2f4909),
                bytes32(0x21afdf725b2bd2c72eb60259f9aa4b041109579101e5bb2a1fbe77906f1b5bcf),
                bytes32(0xc8ebfea0ac3937971c92c24ecc57ce113af0440ce8a7100990cb09b88201e14f),
                bytes32(0x387070bb042159839f7b00ab0958b42ff50e7ee65c07592873842791a0a76ebe),
                bytes32(0xcb435bca4eecc66363416664408044d875dd24ccdbb6710fa077a4e62336fbd9),
                bytes32(0xacce0114f26e3f5ddaed26a260c58582f1570e4da2d07eacc793330102227ab9),
                bytes32(0x2f1662c3e6b862710e1e00a05f7818fd308810ae0939ea1d72ab9eb065fb2cba)
            ],
            [
                bytes32(0xdfcd35b7098e0650cae29057062e64629c586c96f1c3d0cea71a24d3798650a4),
                bytes32(0x10c4d2d6963432bf7037166289dc81edf8f5ef5a5d822a96d1e93dd1c20c7451),
                bytes32(0x40750d788003fa23e6cd06a37bd33db0ff449796f01dce4d56806b2dec1f508a),
                bytes32(0xf31c01c41fcdbb2032397ad6c316b302a95ba1e96bce48b86d3064d61a2f4909),
                bytes32(0x21afdf725b2bd2c72eb60259f9aa4b041109579101e5bb2a1fbe77906f1b5bcf),
                bytes32(0xc8ebfea0ac3937971c92c24ecc57ce113af0440ce8a7100990cb09b88201e14f),
                bytes32(0x387070bb042159839f7b00ab0958b42ff50e7ee65c07592873842791a0a76ebe),
                bytes32(0xcb435bca4eecc66363416664408044d875dd24ccdbb6710fa077a4e62336fbd9),
                bytes32(0xacce0114f26e3f5ddaed26a260c58582f1570e4da2d07eacc793330102227ab9),
                bytes32(0x2f1662c3e6b862710e1e00a05f7818fd308810ae0939ea1d72ab9eb065fb2cba)
            ]
        ];
        bytes32[][] memory proofs = new bytes32[][](2);
        for (uint256 i = 0; i < 2; i++) {
            proofs[i] = new bytes32[](LENGTH);
            for (uint256 j = 0; j < LENGTH; j++) {
                proofs[i][j] = staticProofs[i][j];
            }
        }

        PancakeSwapMerklVault(0x882a41Fd4C5d09D01900DB378903C5C00Cc31D64).compound(tokens, amounts, proofs);

        InstantFarm(0x7051126223a559E3500bd0843924d971f55F0533).updateRewardAmounts();

        vm.stopBroadcast();
    }
}
