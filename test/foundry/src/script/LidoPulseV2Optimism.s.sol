// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../src/strategies/PulseStrategyV2.sol";

import "../../src/utils/DepositWrapper.sol";
import "../../src/utils/UniV3Helper.sol";
import "../../src/utils/PulseStrategyV2Helper.sol";

import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/vaults/UniV3Vault.sol";
import "../../src/vaults/UniV3VaultGovernance.sol";

contract LidoPulseV2 is Script {
    using SafeERC20 for IERC20;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault;

    address public protocolTreasury = 0xAe259ed3699d1416840033ABAf92F9dD4534b2DC;
    address public strategyTreasury = 0xE8Ce688923944eBE6636d7272E7eCA1AECb68E37;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public wsteth = 0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb;
    address public usdc = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;

    address public governance = 0x6CeFdD08d633c4A92380E8F6217238bE2bd1d841;
    address public registry = 0x5cC7Cb6fD996dD646cF613ac94E9E0D2436a083A;
    address public rootGovernance = 0x65a440a89824AB464d7c94B184eF494c1457258D;
    address public erc20Governance = 0xb55ef318B5F73414c91201Af4F467b6c5fE73Ece;
    address public uniV3Governance = 0xdD9E6d6a358640aF0a0C291D7916A37e84Aa40bc;
    address public mellowOracle = 0xA9FC72eE105D43C885E48Ab18148D308A55d04c7;

    UniV3Helper public uniV3Helper = UniV3Helper(0x9eE93e6dDAcC0C3683212A748d5D31eE9043B8F4);

    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    address public oneInchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);
    DepositWrapper public depositWrapper;

    uint256 public constant Q96 = 2 ** 96;

    function firstDeposit(address strategy) public {
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[1] = 10 ** 4;
        tokenAmounts[0] = 10 ** 13;

        if (IERC20(usdc).allowance(msg.sender, address(depositWrapper)) == 0) {
            IERC20(usdc).safeIncreaseAllowance(address(depositWrapper), type(uint128).max);
        }

        if (IERC20(wsteth).allowance(msg.sender, address(depositWrapper)) == 0) {
            IERC20(wsteth).safeApprove(address(depositWrapper), type(uint256).max);
        }

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
    }

    function secondDeposit(address strategy) public {
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[1] = 10 ** 4 * 100;
        tokenAmounts[0] = 10 ** 13 * 100;

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
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
        tokens[1] = usdc;
        tokens[0] = wsteth;
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IUniV3VaultGovernance(uniV3Governance).createVault(tokens, deployer, 500, address(uniV3Helper));

        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        IUniV3VaultGovernance(uniV3Governance).stageDelayedStrategyParams(
            erc20VaultNft + 1,
            IUniV3VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );

        IUniV3VaultGovernance(uniV3Governance).commitDelayedStrategyParams(erc20VaultNft + 1);

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
                router: address(oneInchRouter),
                tokens: erc20Vault.vaultTokens()
            }),
            operator
        );

        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[1] = 1e7;
        minSwapAmounts[0] = 5e15;

        strategy.updateMutableParams(
            PulseStrategyV2.MutableParams({
                priceImpactD6: 0,
                defaultIntervalWidth: 4200,
                maxPositionLengthInTicks: 15000,
                maxDeviationForVaultPool: 50,
                timespanForAverageTick: 60,
                neighborhoodFactorD: 150000000,
                extensionFactorD: 2000000000,
                swapSlippageD: 10000000,
                swappingAmountsCoefficientD: 10000000,
                minSwapAmounts: minSwapAmounts
            })
        );

        strategy.updateDesiredAmounts(PulseStrategyV2.DesiredAmounts({amount0Desired: 1e6, amount1Desired: 1e9}));
    }

    PulseStrategyV2 public baseStrategy;
    PulseStrategyV2Helper public strategyHelper;

    function deployContracts() public {
        depositWrapper = new DepositWrapper(deployer);
        baseStrategy = new PulseStrategyV2(positionManager);
        strategyHelper = new PulseStrategyV2Helper();
    }

    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        UniV3VaultGovernance newUniV3VaultGovernance = new UniV3VaultGovernance(
            IVaultGovernance.InternalParams({
                protocolGovernance: IProtocolGovernance(governance),
                registry: IVaultRegistry(registry),
                singleton: IVault(new UniV3Vault())
            }),
            IUniV3VaultGovernance.DelayedProtocolParams({
                positionManager: positionManager,
                oracle: IOracle(mellowOracle)
            })
        );

        console2.log(address(newUniV3VaultGovernance));

        vm.stopBroadcast();
    }

    // deploy
    function _run() external {
        TransparentUpgradeableProxy newStrategy;
        {
            vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

            deployContracts();

            newStrategy = new TransparentUpgradeableProxy(address(baseStrategy), deployer, new bytes(0));

            deployVaults(address(newStrategy));
            firstDeposit(address(newStrategy));

            IERC20(usdc).safeTransfer(address(newStrategy), 1e6);
            IERC20(wsteth).safeTransfer(address(newStrategy), 1e11);

            vm.stopBroadcast();
        }

        {
            vm.startBroadcast(vm.envUint("OPERATOR_PK"));

            initializeStrategy(PulseStrategyV2(address(newStrategy)));

            PulseStrategyV2(address(newStrategy)).rebalance(type(uint256).max, new bytes(0), 0);
            vm.stopBroadcast();
        }

        {
            vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
            secondDeposit(address(newStrategy));
            vm.stopBroadcast();
        }
    }
}
