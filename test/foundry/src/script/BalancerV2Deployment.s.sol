// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IVault as IBalancerVault, IAsset, IERC20 as IBalancerERC20} from "../../src/interfaces/external/balancer/vault/IVault.sol";
import {IBasePool} from "../../src/interfaces/external/balancer/vault/IBasePool.sol";

import "../../src/strategies/SingleVaultStrategy.sol";

import "../../src/utils/DepositWrapper.sol";

import "../../src/vaults/ERC20Vault.sol";
import "../../src/vaults/ERC20VaultGovernance.sol";

import "../../src/vaults/ERC20RootVault.sol";
import "../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../src/vaults/BalancerV2Vault.sol";
import "../../src/vaults/BalancerV2VaultGovernance.sol";

contract BalancerV2Deployment is Script {
    using SafeERC20 for IERC20;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IBalancerV2Vault public balancerV2Vault;

    address public protocolTreasury = 0x330CEcD19FC9460F7eA8385f9fa0fbbD673798A7;
    address public strategyTreasury = 0x25C2B22477eD2E4099De5359d376a984385b4518;
    address public deployer = 0x7ee9247b6199877F86703644c97784495549aC5E;
    address public operator = 0xE4445221cF7e2070C2C1928d0B3B3e99A0D4Fb8E;

    address public gho = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public wsteth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address public governance = 0xDc9C17662133fB865E7bA3198B67c53a617B2153;
    address public registry = 0xFD23F971696576331fCF96f80a20B4D3b31ca5b2;
    address public rootGovernance = 0x973495e81180Cd6Ead654328A0bEbE01c8ad53EA;
    address public erc20Governance = 0x0bf7B603389795E109a13140eCb07036a1534573;
    address public mellowOracle = 0x9d992650B30C6FB7a83E7e7a430b4e015433b838;

    BalancerV2VaultGovernance public balancerV2VaultGovernance =
        BalancerV2VaultGovernance(0xD7460e3d96Bc845aD4a8d33b7894710dBE205FE5);

    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(rootGovernance);
    DepositWrapper public depositWrapper = DepositWrapper(0x231002439E1BD5b610C3d98321EA760002b9Ff64);

    address public constant GHO_WSTETH_POOL = 0x7D98f308Db99FDD04BbF4217a4be8809F38fAa64;
    address public constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;

    function firstDeposit() public {
        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 10 ** 10;
        tokenAmounts[1] = 10 ** 10;

        if (IERC20(gho).allowance(msg.sender, address(depositWrapper)) == 0) {
            IERC20(gho).safeIncreaseAllowance(address(depositWrapper), type(uint128).max);
        }

        if (IERC20(wsteth).allowance(msg.sender, address(depositWrapper)) == 0) {
            IERC20(wsteth).safeApprove(address(depositWrapper), type(uint256).max);
        }

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), false);
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
        tokens[0] = gho;
        tokens[1] = wsteth;

        IERC20VaultGovernance(erc20Governance).createVault(tokens, deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IBalancerV2VaultGovernance(balancerV2VaultGovernance).createVault(
            tokens,
            deployer,
            GHO_WSTETH_POOL,
            0xBA12222222228d8Ba445958a75a0704d566BF2C8,
            0x6EE63656BbF5BE3fdF9Be4982BF9466F6a921b83,
            0x239e55F427D44C3cc793f49bFB507ebe76638a2b
        );

        balancerV2Vault = IBalancerV2Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        strategy = new SingleVaultStrategy(erc20Vault, address(balancerV2Vault));

        IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](2);
        swaps[0] = IBalancerVault.BatchSwapStep({
            poolId: IBasePool(0x05Bb9b340D21Fc5A0D730EcD1CA79584Fe88E5b8).getPoolId(),
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: 0,
            userData: new bytes(0)
        });
        swaps[1] = IBalancerVault.BatchSwapStep({
            poolId: IBasePool(0x7D98f308Db99FDD04BbF4217a4be8809F38fAa64).getPoolId(),
            assetInIndex: 1,
            assetOutIndex: 2,
            amount: 0,
            userData: new bytes(0)
        });

        IAsset[] memory assets = new IAsset[](3);
        assets[0] = IAsset(BAL);
        assets[1] = IAsset(WSTETH);
        assets[2] = IAsset(GHO);

        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(balancerV2Vault),
            fromInternalBalance: false,
            recipient: payable(address(erc20Vault)),
            toInternalBalance: false
        });
        IAggregatorV3 rewardOracle = IAggregatorV3(0xdF2917806E30300537aEB49A7663062F4d1F2b5F);
        IAggregatorV3 underlyingOracle = IAggregatorV3(0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC);
        uint256 slippageD = 1e8;

        IBalancerV2VaultGovernance.StrategyParams memory strategyParams = IBalancerV2VaultGovernance.StrategyParams({
            swaps: swaps,
            assets: assets,
            funds: funds,
            rewardOracle: rewardOracle,
            underlyingOracle: underlyingOracle,
            slippageD: slippageD
        });

        balancerV2VaultGovernance.setStrategyParams(balancerV2Vault.nft(), strategyParams);
        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(address(strategy), tokens, nfts);
        }
    }

    SingleVaultStrategy public strategy;

    // deploy
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        deployVaults();
        firstDeposit();

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 1e19;
        tokenAmounts[1] = 1e19;
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));

        vm.stopBroadcast();
    }
}
