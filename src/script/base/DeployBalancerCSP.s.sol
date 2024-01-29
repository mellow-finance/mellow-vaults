// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/src/Script.sol";
import "forge-std/src/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IVault as IBalancerVault, IAsset, IERC20 as IBalancerERC20} from "../../../src/interfaces/external/balancer/vault/IVault.sol";
import {IBasePool} from "../../../src/interfaces/external/balancer/vault/IBasePool.sol";

import "../../../src/strategies/BalancerVaultStrategy.sol";
import "../../../src/strategies/BalancerVaultStrategyFix.sol";

import "../../../src/utils/DepositWrapper.sol";

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
        uint256[] memory tokenAmounts = new uint256[](2);

        tokenAmounts[0] = 2e16;
        tokenAmounts[1] = 4e16;

        // if (IERC20(Constants.wsteth).allowance(msg.sender, address(depositWrapper)) == 0) {
        //     IERC20(Constants.wsteth).safeIncreaseAllowance(address(depositWrapper), type(uint128).max);
        // }

        // if (IERC20(Constants.weth).allowance(msg.sender, address(depositWrapper)) == 0) {
        //     IERC20(Constants.weth).safeApprove(address(depositWrapper), type(uint256).max);
        // }

        // depositWrapper.addNewStrategy(address(rootVault), address(strategy), true);
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
            Constants.openOceanRouter
        );
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = Constants.usdc;
        BalancerVaultStrategy(address(strategy)).setRewardTokens(rewardTokens);
    }

    function deployVaults() public {
        IVaultRegistry vaultRegistry = IVaultRegistry(Constants.registry);
        uint256 erc20VaultNft = vaultRegistry.vaultsCount() + 1;

        address[] memory tokens = new address[](2);

        tokens[0] = Constants.wsteth;
        tokens[1] = Constants.weth;
        // PermissionsCheck.checkTokens(tokens);

        IERC20VaultGovernance(Constants.erc20Governance).createVault(tokens, Constants.deployer);
        erc20Vault = IERC20Vault(vaultRegistry.vaultForNft(erc20VaultNft));

        IBalancerV2VaultGovernance(Constants.balancerCSPVaultGovernance).createVault(
            tokens,
            Constants.deployer,
            Constants.balancerWstethWethPool,
            Constants.balancerVault,
            Constants.balancerWstethWethStakinig,
            address(1)
        );

        balancerVault = IBalancerV2Vault(vaultRegistry.vaultForNft(erc20VaultNft + 1));
        IBalancerVault.FundManagement memory funds = IBalancerVault.FundManagement({
            sender: address(balancerVault),
            fromInternalBalance: false,
            recipient: payable(address(strategy)),
            toInternalBalance: false
        });

        IBalancerV2VaultGovernance.StrategyParams memory strategyParams = IBalancerV2VaultGovernance.StrategyParams({
            swaps: new IBalancerVault.BatchSwapStep[](1),
            assets: new IAsset[](2),
            funds: funds,
            rewardOracle: IAggregatorV3(address(strategy)),
            underlyingOracle: IAggregatorV3(address(strategy)),
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

    function deployGovernances() public {
        BalancerV2CSPVault singleton = new BalancerV2CSPVault();
        BalancerV2CSPVaultGovernance newGov = new BalancerV2CSPVaultGovernance(
            IVaultGovernance.InternalParams({
                singleton: singleton,
                registry: IVaultRegistry(Constants.registry),
                protocolGovernance: IProtocolGovernance(Constants.governance)
            })
        );
        console2.log("New governance: ", address(newGov));
    }

    // deploy
    function run() external {
        // vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        // deployGovernances();

        // baseStrategy = BalancerVaultStrategy(0xcE093389454B05aAEB045146A1952c0e46Ddd853);
        // strategy = new TransparentUpgradeableProxy(address(baseStrategy), Constants.deployer, new bytes(0));
        // deployVaults();
        // vm.stopBroadcast();

        // vm.startBroadcast(vm.envUint("OPERATOR_PK"));
        // initializeStrategy();
        // vm.stopBroadcast();

        // rootVault = IERC20RootVault(0x5778D083232f6070E0dF1eBD90940600FE37B638);

        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        deployGovernances();
        vm.stopBroadcast();

        // vm.startBroadcast(vm.envUint("OPERATOR_PK"));
        // BalancerVaultStrategy(address(strategy)).compound(new bytes[](1), type(uint256).max);
        // vm.stopBroadcast();
    }
}
