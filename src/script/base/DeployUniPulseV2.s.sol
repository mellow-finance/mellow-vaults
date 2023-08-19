// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/interfaces/external/univ3/ISwapRouter.sol";

import "../../../src/strategies/PulseStrategyV2.sol";

import "../../../src/utils/DepositWrapper.sol";
import "../../../src/utils/UniV3Helper.sol";
import "../../../src/utils/PulseStrategyV2Helper.sol";

import "../../../src/vaults/ERC20Vault.sol";
import "../../../src/vaults/ERC20VaultGovernance.sol";

import "../../../src/vaults/ERC20RootVault.sol";
import "../../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../../src/vaults/UniV3Vault.sol";
import "../../../src/vaults/UniV3VaultGovernance.sol";

import "./Constants.sol";

contract Deploy is Script {
    using SafeERC20 for IERC20;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault;

    UniV3VaultGovernance public uniV3VaultGovernance = UniV3VaultGovernance(Constants.uniV3Governance);
    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(Constants.erc20RootGovernance);
    DepositWrapper public depositWrapper = DepositWrapper(Constants.depositWrapper);
    UniV3Helper public vaultHelper = UniV3Helper(Constants.uniV3Helper);

    function firstDeposit(address strategy) public {
        uint256[] memory tokenAmounts = new uint256[](2);

        tokenAmounts[0] = 10**13;
        tokenAmounts[1] = 10**4;

        if (IERC20(Constants.weth).allowance(msg.sender, address(depositWrapper)) == 0) {
            IERC20(Constants.weth).safeApprove(address(depositWrapper), type(uint256).max);
        }

        if (IERC20(Constants.usdc).allowance(msg.sender, address(depositWrapper)) == 0) {
            IERC20(Constants.usdc).safeIncreaseAllowance(address(depositWrapper), type(uint128).max);
        }

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
    }

    function combineVaults(
        address strategy_,
        address[] memory tokens,
        uint256[] memory nfts
    ) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(Constants.registry);
        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        uint256 nft;
        (rootVault, nft) = rootVaultGovernance.createVault(tokens, address(strategy_), nfts, Constants.deployer);
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
                strategyTreasury: Constants.strategyTreasury,
                strategyPerformanceTreasury: Constants.protocolTreasury,
                managementFee: 0,
                performanceFee: 0,
                privateVault: true,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        address[] memory wl = new address[](1);
        wl[0] = Constants.depositWrapper;
        rootVault.addDepositorsToAllowlist(wl);

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function deployVaults(address strategy) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(Constants.registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = Constants.weth;
        tokens[1] = Constants.usdc;

        IERC20VaultGovernance(Constants.erc20Governance).createVault(tokens, Constants.deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        uniV3VaultGovernance.createVault(tokens, Constants.deployer, 500, address(vaultHelper));

        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));
        uniV3VaultGovernance.stageDelayedStrategyParams(
            erc20VaultNft + 1,
            IUniV3VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );

        uniV3VaultGovernance.commitDelayedStrategyParams(erc20VaultNft + 1);

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(address(strategy), tokens, nfts);
        }
    }

    function initializeStrategy(PulseStrategyV2 strategy) public {
        strategy.initialize(
            PulseStrategyV2.ImmutableParams({
                erc20Vault: erc20Vault,
                uniV3Vault: uniV3Vault,
                router: address(Constants.openOceanRouter),
                tokens: erc20Vault.vaultTokens()
            }),
            Constants.operator
        );

        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 5e15;
        minSwapAmounts[1] = 1e7;

        strategy.updateMutableParams(
            PulseStrategyV2.MutableParams({
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

        strategy.updateDesiredAmounts(PulseStrategyV2.DesiredAmounts({amount0Desired: 1e6, amount1Desired: 1e9}));
    }

    PulseStrategyV2 public baseStrategy =
        new PulseStrategyV2(INonfungiblePositionManager(Constants.uniswapPositionManager));
    PulseStrategyV2Helper public strategyHelper = new PulseStrategyV2Helper();

    // deploy
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        TransparentUpgradeableProxy newStrategy = new TransparentUpgradeableProxy(
            address(baseStrategy),
            Constants.deployer,
            new bytes(0)
        );

        deployVaults(address(newStrategy));
        firstDeposit(address(newStrategy));

        IERC20(Constants.usdc).safeTransfer(address(newStrategy), 1e6);
        IERC20(Constants.weth).safeTransfer(address(newStrategy), 1e11);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("OPERATOR_PK"));

        initializeStrategy(PulseStrategyV2(address(newStrategy)));

        PulseStrategyV2(address(newStrategy)).rebalance(type(uint256).max, "", 0);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        depositWrapper.addNewStrategy(address(rootVault), address(newStrategy), true);

        vm.stopBroadcast();
    }
}
