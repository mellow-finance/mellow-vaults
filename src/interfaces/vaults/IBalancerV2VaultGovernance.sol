// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IVault as IBalancerVault, IERC20 as IBalancerERC20} from "../external/balancer/vault/IVault.sol";

import {IManagedPool} from "../external/balancer/pool-utils/IManagedPool.sol";

import {IStakingLiquidityGauge} from "../external/balancer/liquidity-mining/IStakingLiquidityGauge.sol";
import {IBalancerMinter} from "../external/balancer/liquidity-mining/IBalancerMinter.sol";

import {WeightedPoolUserData} from "../external/balancer/pool-weighted/WeightedPoolUserData.sol";
import {StablePoolUserData} from "../external/balancer/pool-stable/StablePoolUserData.sol";

import "./IBalancerV2Vault.sol";
import "./IVaultGovernance.sol";
import "./IIntegrationVault.sol";

interface IBalancerV2VaultGovernance is IVaultGovernance {
    struct StrategyParams {
        IBalancerVault.BatchSwapStep[] swaps;
        IAsset[] assets;
        IBalancerVault.FundManagement funds;
        IAggregatorV3 rewardOracle;
        IAggregatorV3 underlyingOracle;
        uint256 slippageD;
    }

    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        address pool_,
        address balancerVault_,
        address stakingLiquidityGauge_,
        address balancerMinter_
    ) external returns (IBalancerV2Vault vault, uint256 nft);

    /// @notice Delayed Strategy Params
    /// @param nft VaultRegistry NFT of the vault
    function strategyParams(uint256 nft) external view returns (StrategyParams memory);

    /// @notice Delayed Strategy Params staged for commit after delay.
    /// @param nft VaultRegistry NFT of the vault
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external;
}
