// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";
import "forge-std/src/console2.sol";

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../strategies/BasePulseStrategy.sol";
import "../../strategies/OlympusConcentratedStrategy.sol";

import "../../utils/DepositWrapper.sol";
import "../../utils/BasePulseStrategyHelper.sol";
import "../../utils/UniV3Helper.sol";

import "../../vaults/ERC20Vault.sol";
import "../../vaults/ERC20VaultGovernance.sol";

import "../../vaults/ERC20RootVault.sol";
import "../../vaults/ERC20RootVaultGovernance.sol";

import "../../vaults/UniV3Vault.sol";
import "../../vaults/UniV3VaultGovernance.sol";

contract Deploy is Script {
    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IUniV3Vault public uniV3Vault;

    address public protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address public strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;

    address public ohm = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address public inchRouter = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public uniV3VaultGovernance = 0x9c319DC47cA6c8c5e130d5aEF5B8a40Cce9e877e;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    INonfungiblePositionManager public positionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    DepositWrapper public depositWrapper = DepositWrapper(0x231002439E1BD5b610C3d98321EA760002b9Ff64);

    TransparentUpgradeableProxy public strategy;
    OlympusConcentratedStrategy public olympusStrategy;

    BasePulseStrategyHelper public strategyHelper = BasePulseStrategyHelper(0x7c59Aae0Ee2EeEdeC34d235FeAF91A45CcAE2cb5);

    uint256 public constant Q96 = 2**96;

    function combineVaults(uint256[] memory nfts) public {
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

        {
            address[] memory whitelist = new address[](1);
            whitelist[0] = address(depositWrapper);
            rootVault.addDepositorsToAllowlist(whitelist);
        }

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

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    address[] public tokens;

    function deploySubvaults() public returns (uint256[] memory nfts) {
        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        tokens.push(ohm);
        tokens.push(usdc);
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IUniV3VaultGovernance(uniV3VaultGovernance).createVault(
            tokens,
            deployer,
            3000,
            0xA995B345d22Db15c9a36Cb6928967AFCFAb84fDb
        );

        uniV3Vault = IUniV3Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        IUniV3VaultGovernance(uniV3VaultGovernance).stageDelayedStrategyParams(
            erc20VaultNft + 1,
            IUniV3VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );
        IUniV3VaultGovernance(uniV3VaultGovernance).commitDelayedStrategyParams(erc20VaultNft + 1);

        nfts = new uint256[](2);
        nfts[0] = erc20VaultNft;
        nfts[1] = erc20VaultNft + 1;
    }

    function deployContracts() public {
        uint256[] memory nfts = deploySubvaults();
        deployStrategies();
        combineVaults(nfts);
        initStrategies();
    }

    function deposit(uint256 coef) public {
        uint256 totalSupply = rootVault.totalSupply();
        uint256[] memory tokenAmounts = rootVault.pullExistentials();
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenAmounts[i] *= 10 * coef;
        }
        if (totalSupply == 0) {
            for (uint256 i = 0; i < tokens.length; i++) {
                IERC20(tokens[i]).approve(address(depositWrapper), type(uint256).max);
            }
            depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
        } else {
            depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
        }
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
    }

    address public constant BASE_STRATEGY_ADDRESS = 0x0c896de0ED46517C8206b82ff7D7824D30892F14;
    address public constant MAINNET_PROTOCOL_ADMIN_ADDRESS = 0x565766498604676D9916D4838455Cc5fED24a5B3;
    address public constant MAINNET_STRATEGY_ADMIN_ADDRESS = 0x1EB0D48bF31caf9DBE1ad2E35b3755Fdf2898068;

    function deployStrategies() public {
        strategy = new TransparentUpgradeableProxy(BASE_STRATEGY_ADDRESS, MAINNET_PROTOCOL_ADMIN_ADDRESS, "");
        olympusStrategy = new OlympusConcentratedStrategy(
            deployer,
            BasePulseStrategy(address(strategy)),
            IOlympusRange(0xb212D9584cfc56EFf1117F412Fe0bBdc53673954),
            60,
            9,
            6,
            18,
            true
        );
        olympusStrategy.updateMutableParams(
            OlympusConcentratedStrategy.MutableParams({intervalWidth: 600, tickNeighborhood: 120})
        );

        IERC20(ohm).transfer(address(strategy), 1e4);
        IERC20(usdc).transfer(address(strategy), 1e4);
    }

    function initStrategies() public {
        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e8;
        minSwapAmounts[1] = 1e6;

        BasePulseStrategy(address(strategy)).initialize(
            BasePulseStrategy.ImmutableParams({
                erc20Vault: erc20Vault,
                uniV3Vault: uniV3Vault,
                router: address(0x1111111254EEB25477B68fb85Ed929f73A960582),
                tokens: erc20Vault.vaultTokens()
            }),
            deployer
        );

        BasePulseStrategy(address(strategy)).updateMutableParams(
            BasePulseStrategy.MutableParams({
                priceImpactD6: 0,
                maxDeviationForVaultPool: 50,
                timespanForAverageTick: 60,
                swapSlippageD: 1e7,
                swappingAmountsCoefficientD: 1e7,
                minSwapAmounts: minSwapAmounts
            })
        );

        BasePulseStrategy(address(strategy)).updateDesiredAmounts(
            BasePulseStrategy.DesiredAmounts({amount0Desired: 1e4, amount1Desired: 1e4})
        );
    }

    function rebalance() public {
        BasePulseStrategy.Interval memory interval = olympusStrategy.calculateInterval();

        console2.log("New interval:", vm.toString(interval.lowerTick), vm.toString(interval.upperTick));

        BasePulseStrategy(address(strategy)).grantRole(
            BasePulseStrategy(address(strategy)).ADMIN_DELEGATE_ROLE(),
            address(deployer)
        );
        BasePulseStrategy(address(strategy)).grantRole(
            BasePulseStrategy(address(strategy)).OPERATOR(),
            address(olympusStrategy)
        );

        olympusStrategy.rebalance(type(uint256).max, new bytes(0), 0);
    }

    function run() external {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));
        deployContracts();
        deposit(1);
        rebalance();
        deposit(1000);
        vm.stopBroadcast();
    }
}
