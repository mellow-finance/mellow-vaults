// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IAsset} from "../../../src/interfaces/external/balancer/vault/IVault.sol";
import {IBasePool} from "../../../src/interfaces/external/balancer/vault/IBasePool.sol";

import "../../../src/vaults/AuraVault.sol";
import "../../../src/vaults/AuraVaultGovernance.sol";

import "../../../src/vaults/ERC20RootVault.sol";
import "../../../src/vaults/ERC20RootVaultGovernance.sol";

import "../../../src/vaults/ERC20Vault.sol";
import "../../../src/vaults/ERC20VaultGovernance.sol";

import "../../../src/utils/DepositWrapper.sol";
import {AuraOracle} from "../../../src/oracles/AuraOracle.sol";

import "../../../src/strategies/SingleVaultStrategy.sol";

import "./Constants.sol";

contract AuraDeployment is Script {
    using SafeERC20 for IERC20;

    IERC20RootVaultGovernance public rootVaultGovernance = IERC20RootVaultGovernance(Constants.erc20RootGovernance);
    DepositWrapper public depositWrapper = DepositWrapper(Constants.depositWrapper);

    IERC20RootVault rootVault;
    IERC20Vault erc20Vault;
    IAuraVault auraVault;
    SingleVaultStrategy strategy;

    AuraOracle auraOracle;

    function deposit() public {
        IERC20(Constants.lusd).approve(address(depositWrapper), type(uint256).max);
        IERC20(Constants.gho).approve(address(depositWrapper), type(uint256).max);

        uint256[] memory tokenAmounts = new uint256[](2);
        tokenAmounts[0] = 1e10;
        tokenAmounts[1] = 1e10;
        depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
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

    function deployVaults() public {
        IVaultRegistry vaultRegistry = IVaultRegistry(Constants.registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);
        tokens[0] = Constants.gho;
        tokens[1] = Constants.lusd;

        IERC20VaultGovernance(Constants.erc20Governance).createVault(tokens, Constants.deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IAuraVaultGovernance(Constants.auraVaultGovernance).createVault(
            tokens,
            Constants.deployer,
            Constants.balancerGhoLusdPool,
            Constants.balancerVault,
            0xA57b8d98dAE62B26Ec3bcC4a365338157060B234,
            0x9305F7B6017c08BB71004A85fd78Adf3E32ce5CE
        );

        auraVault = IAuraVault(vaultRegistry.vaultForNft(erc20VaultNft + 1));

        IAuraVaultGovernance.SwapParams[] memory swapParams = new IAuraVaultGovernance.SwapParams[](2);
        {
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

            IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
                sender: address(auraVault),
                fromInternalBalance: false,
                recipient: payable(address(erc20Vault)),
                toInternalBalance: false
            });
            IAggregatorV3 rewardOracle = IAggregatorV3(0xdF2917806E30300537aEB49A7663062F4d1F2b5F);
            IAggregatorV3 underlyingOracle = IAggregatorV3(0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC);
            uint256 slippageD = 1e8;
            swapParams[0] = IAuraVaultGovernance.SwapParams({
                swaps: swaps,
                assets: assets,
                funds: funds,
                rewardOracle: rewardOracle,
                underlyingOracle: underlyingOracle,
                slippageD: slippageD
            });
        }

        {
            IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](3);
            swaps[0] = IBalancerVault.BatchSwapStep({
                poolId: IBasePool(0xCfCA23cA9CA720B6E98E3Eb9B6aa0fFC4a5C08B9).getPoolId(),
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
            assets[0] = IAsset(Constants.aura);
            assets[1] = IAsset(Constants.weth);
            assets[2] = IAsset(Constants.wsteth);
            assets[3] = IAsset(Constants.gho);

            IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
                sender: address(auraVault),
                fromInternalBalance: false,
                recipient: payable(address(erc20Vault)),
                toInternalBalance: false
            });

            IAggregatorV3 rewardOracle = auraOracle;
            IAggregatorV3 underlyingOracle = IAggregatorV3(0x3f12643D3f6f874d39C2a4c9f2Cd6f2DbAC877FC);
            uint256 slippageD = 2e8;
            swapParams[1] = IAuraVaultGovernance.SwapParams({
                swaps: swaps,
                assets: assets,
                funds: funds,
                rewardOracle: rewardOracle,
                underlyingOracle: underlyingOracle,
                slippageD: slippageD
            });
        }

        IAuraVaultGovernance.StrategyParams memory strategyParams = IAuraVaultGovernance.StrategyParams(swapParams);

        IAuraVaultGovernance(Constants.auraVaultGovernance).setStrategyParams(auraVault.nft(), strategyParams);
        strategy = new SingleVaultStrategy(erc20Vault, address(auraVault));

        {
            uint256[] memory nfts = new uint256[](2);
            nfts[0] = erc20VaultNft;
            nfts[1] = erc20VaultNft + 1;
            combineVaults(tokens, nfts);
        }
    }

    // rebalance
    function run() external {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));

        auraOracle = new AuraOracle();

        deployVaults();
        deposit();
        {
            (uint256[] memory tvlBeforeClaim, ) = rootVault.tvl();
            console2.log(tvlBeforeClaim[0], tvlBeforeClaim[1]);
        }

        if (false) {
            auraVault.claimRewards();
            {
                (uint256[] memory tvlBeforeClaim, ) = rootVault.tvl();
                console2.log(tvlBeforeClaim[0], tvlBeforeClaim[1]);
            }

            uint256[] memory tokenAmounts = new uint256[](2);
            tokenAmounts[0] = 1e18 * 10;
            tokenAmounts[1] = 1e18 * 10;
            depositWrapper.deposit(rootVault, tokenAmounts, 0, new bytes(0));
        }
        vm.stopBroadcast();
    }
}
