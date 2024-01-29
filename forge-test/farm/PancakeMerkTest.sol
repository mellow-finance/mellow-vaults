// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Test.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../src/vaults/PancakeSwapMerklVaultGovernance.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/PancakeSwapMerklVault.sol";
import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20Vault.sol";

import "../../src/utils/StakingDepositWrapper.sol";
import "../../src/utils/PancakeSwapMerklHelper.sol";

import "../../src/utils/InstantFarm.sol";

import "../../src/strategies/PancakeSwapMerklPulseStrategyV2.sol";

contract PancakeMerklTest is Test {
    using SafeERC20 for IERC20;

    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CAKE = 0x152649eA73beAb28c5b49B26eb48f7EAD6d4c898;
    address public constant RPL = 0xD33526068D116cE69F19A9ee46F0bd304F21A51f;

    address public sAdmin = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;
    address public protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address public strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0x136348814f89fcbF1a0876Ca853D48299AFB8b3c;

    address public admin = 0x565766498604676D9916D4838455Cc5fED24a5B3;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    IPancakeNonfungiblePositionManager public immutable positionManager =
        IPancakeNonfungiblePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);

    IPancakeSwapMerklVaultGovernance public pancakeGovernance;
    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);
    StakingDepositWrapper public depositWrapper = new StakingDepositWrapper(deployer);

    uint256 public constant Q96 = 2**96;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IPancakeSwapMerklVault public pancakeVault;
    InstantFarm public lpFarm;

    PancakeSwapMerklPulseStrategyV2 public strategy;

    function withdraw() public returns (uint256[] memory amounts) {
        vm.startPrank(deployer);
        uint256 lpAmount = lpFarm.balanceOf(deployer) / 2;
        lpFarm.withdraw(lpAmount, deployer);
        amounts = rootVault.withdraw(deployer, lpAmount, new uint256[](2), new bytes[](2));
        vm.stopPrank();
    }

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
        vm.startPrank(deployer);
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
                router: 0x1111111254EEB25477B68fb85Ed929f73A960582,
                tokens: erc20Vault.vaultTokens()
            }),
            operator
        );
        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }

        lpFarm = new InstantFarm(address(rootVault), deployer, rewards);

        vm.stopPrank();
    }

    function deployGovernances() public {
        pancakeGovernance = new PancakeSwapMerklVaultGovernance(
            IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: IVaultRegistry(registry),
                singleton: IVault(address(new PancakeSwapMerklVault()))
            }),
            IPancakeSwapMerklVaultGovernance.DelayedProtocolParams({
                positionManager: positionManager,
                oracle: IOracle(mellowOracle)
            })
        );

        vm.startPrank(admin);
        IProtocolGovernance(governance).stagePermissionGrants(address(pancakeGovernance), new uint8[](1));

        uint8[] memory permissions = new uint8[](2);
        permissions[0] = 2;
        permissions[1] = 3;

        skip(24 * 3600);
        IProtocolGovernance(governance).commitAllPermissionGrantsSurpassedDelay();

        vm.stopPrank();
    }

    // function deposit() public {
    //     (, uint256[] memory tvl) = rootVault.tvl();

    //     if (tvl[0] == 0) {
    //         tvl = new uint256[](2);
    //         tvl[0] = 1e10 * 76;
    //         tvl[1] = 1e10 * 23;
    //     } else {
    //         tvl[0] *= 10;
    //         tvl[1] *= 10;
    //         tvl[0] /= 3;
    //         tvl[1] /= 3;
    //     }

    //     deal(GHO, deployer, tvl[0]);
    //     deal(LUSD, deployer, tvl[1]);

    //     vm.startPrank(deployer);
    //     IERC20(LUSD).approve(address(depositWrapper), type(uint256).max);
    //     IERC20(GHO).approve(address(depositWrapper), type(uint256).max);

    //     depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
    //     depositWrapper.deposit(rootVault, tvl, 0, new bytes(0));

    //     vm.stopPrank();
    // }

    function deposit() public {
        vm.startPrank(deployer);
        uint256[] memory amounts = new uint256[](2);
        if (rootVault.totalSupply() == 0) {
            amounts[0] = 1e14;
            amounts[1] = 1e14;
            depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
            deal(RETH, address(strategy), 1e14);
            deal(WETH, address(strategy), 1e14);
        } else {
            (amounts, ) = rootVault.tvl();
            amounts[0] *= 2;
            amounts[1] *= 2;
            depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
        }

        deal(RETH, deployer, amounts[0]);
        deal(WETH, deployer, amounts[1]);

        IERC20(RETH).safeApprove(address(depositWrapper), type(uint256).max);
        IERC20(WETH).safeApprove(address(depositWrapper), type(uint256).max);

        depositWrapper.deposit(rootVault, lpFarm, amounts, 0, "");

        IERC20(RETH).safeApprove(address(depositWrapper), 0);
        IERC20(WETH).safeApprove(address(depositWrapper), 0);

        vm.stopPrank();
    }

    function test() external {
        deployGovernances();
        deployVaults();
        vm.startPrank(operator);
        strategy.updateFarms(address(lpFarm), address(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae));

        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e15;
        minSwapAmounts[1] = 1e15;

        strategy.updateMutableParams(
            PancakeSwapMerklPulseStrategyV2.MutableParams({
                priceImpactD6: 0,
                defaultIntervalWidth: 20,
                maxPositionLengthInTicks: 60,
                maxDeviationForVaultPool: 5,
                timespanForAverageTick: 30,
                neighborhoodFactorD: 150000000,
                extensionFactorD: 2000000000,
                swapSlippageD: 10000000,
                swappingAmountsCoefficientD: 10000000,
                minSwapAmounts: minSwapAmounts
            })
        );

        strategy.updateDesiredAmounts(
            PancakeSwapMerklPulseStrategyV2.DesiredAmounts({amount0Desired: 1e9, amount1Desired: 1e9})
        );

        vm.stopPrank();

        deposit();

        vm.startPrank(operator);

        strategy.rebalance(type(uint256).max, "", 0);

        vm.stopPrank();

        deposit();
        deposit();
        deposit();
        (uint256[] memory tvlAfterWithdraw, ) = rootVault.tvl();
        console2.log("tvlBeforeWithdraw: ", tvlAfterWithdraw[0], tvlAfterWithdraw[1]);
        uint256[] memory withdrawedAmount = withdraw();
        (tvlAfterWithdraw, ) = rootVault.tvl();
        console2.log("tvlAfterWithdraw: ", tvlAfterWithdraw[0], tvlAfterWithdraw[1]);
        console2.log("withdrawedAmount: ", withdrawedAmount[0], withdrawedAmount[1]);

        withdraw();
    }
}
