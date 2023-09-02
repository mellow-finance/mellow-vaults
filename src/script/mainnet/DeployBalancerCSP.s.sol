// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IVault as IBalancerVault, IAsset, IERC20 as IBalancerERC20} from "../../../src/interfaces/external/balancer/vault/IVault.sol";
import {IBasePool} from "../../../src/interfaces/external/balancer/vault/IBasePool.sol";

import "../../../src/strategies/BalancerVaultStrategy.sol";

import "../../../src/utils/DepositWrapper.sol";
import "../../../src/utils/OneSidedDepositWrapper.sol";

import "../../../src/vaults/ERC20Vault.sol";
import "../../../src/vaults/ERC20VaultGovernance.sol";

import "../../../src/vaults/ERC20RootVault.sol";
import "../../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../../src/vaults/BalancerV2CSPVault.sol";
import "../../../src/vaults/BalancerV2CSPVaultGovernance.sol";

import "../../../src/utils/BalancerVaultStrategyHelper.sol";

import "./Constants.sol";

// import "./PermissionsCheck.sol";

contract Deploy is Script {
    using SafeERC20 for IERC20;

    IERC20RootVault public rootVault;
    IERC20Vault public erc20Vault;
    IBalancerV2Vault public balancerVault;

    BalancerV2CSPVaultGovernance public balancerVaultGovernance =
        BalancerV2CSPVaultGovernance(Constants.balancerCSPVaultGovernance);
    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(Constants.erc20RootGovernance);
    DepositWrapper public depositWrapper = DepositWrapper(Constants.depositWrapper);

    function firstDeposit() public {
        uint256[] memory tokenAmounts = new uint256[](3);

        tokenAmounts[0] = 1e18;
        tokenAmounts[1] = 1e6;
        tokenAmounts[2] = 1e6;

        if (IERC20(Constants.gho).allowance(Constants.deployer, address(depositWrapper)) == 0) {
            IERC20(Constants.gho).safeApprove(address(depositWrapper), type(uint256).max);
        }

        if (IERC20(Constants.usdc).allowance(Constants.deployer, address(depositWrapper)) == 0) {
            IERC20(Constants.usdc).safeIncreaseAllowance(address(depositWrapper), type(uint128).max);
        }

        if (IERC20(Constants.usdt).allowance(Constants.deployer, address(depositWrapper)) == 0) {
            IERC20(Constants.usdt).safeApprove(address(depositWrapper), type(uint256).max);
        }

        depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));

        tokenAmounts[0] *= 5;
        tokenAmounts[1] *= 5;
        tokenAmounts[2] *= 5;

        depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
    }

    function combineVaults(address[] memory tokens, uint256[] memory nfts) public {
        IVaultRegistry vaultRegistry = IVaultRegistry(Constants.registry);
        for (uint256 i = 0; i < nfts.length; ++i) {
            vaultRegistry.approve(address(rootVaultGovernance), nfts[i]);
        }

        uint256 nft;
        (rootVault, nft) = rootVaultGovernance.createVault(tokens, address(strategy), nfts, Constants.deployer);
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
        wl[0] = address(depositWrapper);
        rootVault.addDepositorsToAllowlist(wl);
        rootVaultGovernance.commitDelayedStrategyParams(nft);
    }

    function initializeStrategy() public {
        BalancerVaultStrategy(address(strategy)).initialize(
            Constants.operator,
            erc20Vault,
            address(balancerVault),
            Constants.oneInchRouter
        );
        // address[] memory rewardTokens = new address[](1);
        // rewardTokens[0] = Constants.usdc;
        // BalancerVaultStrategy(address(strategy)).setRewardTokens(rewardTokens);
    }

    function deployVaults() public {
        IVaultRegistry vaultRegistry = IVaultRegistry(Constants.registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](3);

        tokens[0] = Constants.gho;
        tokens[1] = Constants.usdc;
        tokens[2] = Constants.usdt;

        // PermissionsCheck.checkTokens(tokens);

        IERC20VaultGovernance(Constants.erc20Governance).createVault(tokens, Constants.deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IBalancerV2VaultGovernance(Constants.balancerCSPVaultGovernance).createVault(
            tokens,
            Constants.deployer,
            Constants.balancerUsdcUsdtGho,
            Constants.balancerVault,
            Constants.balancerUsdcUsdtGhoStaking,
            Constants.balancerMinter
        );

        balancerVault = IBalancerV2Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));
        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(balancerVault),
            fromInternalBalance: false,
            recipient: payable(address(strategy)),
            toInternalBalance: false
        });

        IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](3);
        swaps[0] = IBalancerVault.BatchSwapStep({
            poolId: IBasePool(0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56).getPoolId(),
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: 0,
            userData: new bytes(0)
        });
        swaps[1] = IBalancerVault.BatchSwapStep({
            poolId: IBasePool(0x32296969Ef14EB0c6d29669C550D4a0449130230).getPoolId(),
            assetInIndex: 1,
            assetOutIndex: 2,
            amount: 0,
            userData: new bytes(0)
        });
        swaps[2] = IBalancerVault.BatchSwapStep({
            poolId: IBasePool(0x7D98f308Db99FDD04BbF4217a4be8809F38fAa64).getPoolId(),
            assetInIndex: 2,
            assetOutIndex: 3,
            amount: 0,
            userData: new bytes(0)
        });

        IAsset[] memory assets = new IAsset[](4);
        assets[0] = IAsset(Constants.bal);
        assets[1] = IAsset(Constants.weth);
        assets[2] = IAsset(Constants.wsteth);
        assets[3] = IAsset(Constants.gho);

        IAggregatorV3 rewardOracle = IAggregatorV3(0xdF2917806E30300537aEB49A7663062F4d1F2b5F);
        IAggregatorV3 underlyingOracle = IAggregatorV3(0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC);

        IBalancerV2VaultGovernance.StrategyParams memory strategyParams = IBalancerV2VaultGovernance.StrategyParams({
            swaps: swaps,
            assets: assets,
            funds: funds,
            rewardOracle: rewardOracle,
            underlyingOracle: underlyingOracle,
            slippageD: 0
        });

        balancerVaultGovernance.setStrategyParams(balancerVault.nft(), strategyParams);
        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }
    }

    BalancerVaultStrategy public baseStrategy;
    TransparentUpgradeableProxy public strategy;

    // deploy
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        OneSidedDepositWrapper wrapper = new OneSidedDepositWrapper(
            Constants.uniswapV3Router,
            Constants.uniswapV3Factory,
            Constants.weth
        );

        console2.log(address(wrapper));

        // baseStrategy = new BalancerVaultStrategy();
        // strategy = new TransparentUpgradeableProxy(address(baseStrategy), Constants.deployer, new bytes(0));
        // deployVaults();

        // vm.stopBroadcast();
        // vm.startBroadcast(vm.envUint("OPERATOR_PK"));

        // initializeStrategy();

        // vm.stopBroadcast();
        // vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        // firstDeposit();

        vm.stopBroadcast();
        // vm.startBroadcast(vm.envUint("OPERATOR_PK"));

        // BalancerVaultStrategy(address(strategy)).compound(new bytes[](0), type(uint256).max);

        // vm.stopBroadcast();
    }
}
