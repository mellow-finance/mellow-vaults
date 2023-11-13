// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../src/interfaces/external/ramses/ISwapRouter.sol";

import "../../../src/utils/StakingDepositWrapper.sol";
import "../../../src/utils/RamsesV2Helper.sol";
import "../../../src/utils/GRamsesStrategyHelper.sol";

import "../../../src/vaults/ERC20Vault.sol";
import "../../../src/vaults/ERC20VaultGovernance.sol";

import "../../../src/vaults/ERC20RootVault.sol";
import "../../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../../src/vaults/RamsesV2Vault.sol";
import "../../../src/vaults/RamsesV2VaultGovernance.sol";

import "../../../src/strategies/GRamsesStrategy.sol";

import "./Constants.sol";

contract Deploy is Script {
    using SafeERC20 for IERC20;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IRamsesV2Vault public lowerVault;
    IRamsesV2Vault public upperVault;

    address public router = 0xAA23611badAFB62D37E7295A682D21960ac85A90;
    address public grai = 0x894134a25a5faC1c2C26F1d8fBf05111a3CB9487;
    address public frax = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;

    address public protocolTreasury = 0xDF6780faC92ec8D5f366584c29599eA1c97C77F5;
    address public strategyTreasury = 0xb0426fDFEfF47B23E5c2794D406A3cC8E77Ec001;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public governance = 0x65a440a89824AB464d7c94B184eF494c1457258D;
    address public registry = 0x7D7fEF7bF8bE4DB0FFf06346C59efc24EE8e4c22;
    address public rootGovernance = 0xC75825C5539968648632ec6207f8EDeC407dF891;
    address public erc20Governance = 0x7D62E2c0516B8e747d95323Ca350c847C4Dea533;
    address public mellowOracle = 0x3EFf1DA9e5f72d51F268937d3A5426c2bf5eFf4A;

    address public erc20Validator = 0xa3420E55cC602a65bFA114A955DB1B1D4CA03745;
    address public allowAllValidator = 0x4c31e14F344CDD2921995C62F7a15Eea6B9E7521;

    IRamsesV2NonfungiblePositionManager public positionManager =
        IRamsesV2NonfungiblePositionManager(0xAA277CB7914b7e5514946Da92cb9De332Ce610EF);
    RamsesV2VaultGovernance public ramsesGovernance =
        RamsesV2VaultGovernance(0xAAa8B17804220f3b45eaFCF75ef760d5c51d5d10);
    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);

    StakingDepositWrapper public depositWrapper;
    RamsesV2Helper public vaultHelper;
    GRamsesStrategy public baseStrategy;

    uint256 public constant Q96 = 2**96;
    address[] public rewards;
    RamsesInstantFarm public lpFarm;

    function deposit(bool flag) public {
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = flag ? 10 ether : 1e15;
        tokenAmounts[1] = flag ? 10 ether : 1e15;

        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));

        if (IERC20(frax).allowance(deployer, address(depositWrapper)) == 0) {
            IERC20(frax).approve(address(depositWrapper), type(uint256).max);
            IERC20(frax).approve(address(depositWrapper), type(uint256).max);
        }

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), flag);
        depositWrapper.deposit(rootVault, lpFarm, tokenAmounts, 0, new bytes(0));

        vm.stopBroadcast();
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
                privateVault: false,
                depositCallbackAddress: address(0),
                withdrawCallbackAddress: address(0)
            })
        );

        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    TransparentUpgradeableProxy public strategy;

    function deployVaults() public {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("DEPLOYER_PK"))));
        depositWrapper = StakingDepositWrapper(0x4c73D851CC149D48120B6e5f9288B836Da421D6D);
        vaultHelper = RamsesV2Helper(0xFE632AB8c274d5c2C9B113f00cd2C4Aa02c37AE4);
        baseStrategy = GRamsesStrategy(0x51BAB0F24FB5Bf86Ed7e0f24C1fC1e312fc86417);
        strategy = new TransparentUpgradeableProxy(address(baseStrategy), deployer, new bytes(0));

        IVaultRegistry vaultRegistry = IVaultRegistry(registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = frax;
        tokens[1] = grai;
        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        ramsesGovernance.createVault(tokens, deployer, 500, address(vaultHelper), address(erc20Vault));
        lowerVault = IRamsesV2Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));
        ramsesGovernance.stageDelayedStrategyParams(
            lowerVault.nft(),
            IRamsesV2VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );
        ramsesGovernance.commitDelayedStrategyParams(lowerVault.nft());

        ramsesGovernance.createVault(tokens, deployer, 500, address(vaultHelper), address(erc20Vault));
        upperVault = IRamsesV2Vault(vaultRegistry.vaultForNft(erc20VaultNft + 2));
        ramsesGovernance.stageDelayedStrategyParams(
            upperVault.nft(),
            IRamsesV2VaultGovernance.DelayedStrategyParams({safetyIndicesSet: 2})
        );
        ramsesGovernance.commitDelayedStrategyParams(upperVault.nft());

        {
            uint256[] memory nfts = new uint256[](3);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            nfts[2] = erc20VaultNft + 2;
            combineVaults(tokens, nfts);
        }

        rewards = new address[](2);
        rewards[0] = ram;
        rewards[1] = xram;

        lpFarm = new RamsesInstantFarm(
            RamsesInstantFarm.InitParams({
                lpToken: address(rootVault),
                admin: deployer,
                rewardTokens: rewards,
                xram: xram,
                ram: ram,
                weth: weth,
                router: address(router),
                wethRamPool: 0x688547381eEC7C1d3d9eBa778fE275D1D7e03946,
                wethPool: 0x2Ed095289b2116D7a3399e278D603A4e4015B19D,
                timespan: 60,
                maxTickDeviation: 50
            })
        );

        IERC20(grai).safeTransfer(address(strategy), 1 ether);
        IERC20(frax).safeTransfer(address(strategy), 1 ether);

        vm.stopBroadcast();
    }

    address public ram = 0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418;
    address public xram = 0xAAA1eE8DC1864AE49185C368e8c64Dd780a50Fb7;
    address public weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function initializeStrategy() public {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("OPERATOR_PK"))));

        GRamsesStrategy(address(strategy)).initialize(
            operator,
            GRamsesStrategy.ImmutableParams({
                fee: 500,
                pool: IRamsesV2Pool(lowerVault.pool()),
                erc20Vault: erc20Vault,
                lowerVault: lowerVault,
                upperVault: upperVault,
                router: router,
                tokens: lowerVault.vaultTokens()
            })
        );

        uint256[] memory minSwapAmounts = new uint256[](2);
        minSwapAmounts[0] = 1e15;
        minSwapAmounts[1] = 1e15;

        GRamsesStrategy(address(strategy)).updateMutableParams(
            GRamsesStrategy.MutableParams({
                timespan: 60,
                maxTickDeviation: 10,
                intervalWidth: 10,
                priceImpactD6: 1000, // 1%
                amount0Desired: 10 gwei,
                amount1Desired: 10 gwei,
                maxRatioDeviationX96: uint256(2**96) / 100,
                swapSlippageD: 1e7,
                swappingAmountsCoefficientD: 1e7,
                minSwapAmounts: minSwapAmounts
            })
        );

        GRamsesStrategy(address(strategy)).updateVaultFarms(
            IRamsesV2VaultGovernance.StrategyParams({
                farm: address(lpFarm),
                rewards: rewards,
                gaugeV2: address(0x8cfBc79E06A80f5931B3F9FCC4BbDfac91D45A50),
                instantExitFlag: true
            })
        );
        vm.stopBroadcast();
    }

    function rebalance() public {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("OPERATOR_PK"))));
        GRamsesStrategy(address(strategy)).rebalance("", 0, type(uint256).max);
        vm.stopBroadcast();
    }

    function run() external {
        deployVaults();
        initializeStrategy();
        deposit(false);
        rebalance();
        deposit(true);
    }
}
