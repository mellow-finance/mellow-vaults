// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IVeloVault.sol";

import "../external/velo/INonfungiblePositionManager.sol";
import "../oracles/IOracle.sol";
import "./IVaultGovernance.sol";

/*
    Interface for the Velodrome Vault Governance contract.
    This contract is responsible for managing Velodrome Vaults and their governance parameters.
*/
interface IVeloVaultGovernance is IVaultGovernance {
    /// @notice Structure containing data for each individual VeloVault.
    /// @notice Address of the CLGauge.
    /// @notice Address of the farm where rewards are sent.
    /// @notice Address of the treasury where a portion of rewards goes.
    /// @notice Parameter determining the portion of rewards going to the protocol treasury, multiplied by 1e9.
    struct StrategyParams {
        address gauge;
        address farmingPool;
        address protocolTreasury;
        uint256 protocolFeeD9;
    }

    /// @notice Get Strategy Params for a specific vault NFT from VelodromeVaultGovernance.
    /// @param nft VaultRegistry NFT of the vault.
    /// @return params The strategy parameters for the vault.
    function strategyParams(uint256 nft) external view returns (StrategyParams memory params);

    /// @notice Set Strategy params, i.e., parameters that could be changed by Strategy or Protocol Governance immediately.
    /// @param nft NFT of the vault.
    /// @param params New parameters.
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external;

    /// @notice Deploys a new vault.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault.
    /// @param owner_ Owner of the vault NFT.
    /// @param tickSpacing_ Tick spacing of the Velodrome pool.
    /// @return vault The created Velodrome Vault contract.
    /// @return nft The NFT ID of the created vault.
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        int24 tickSpacing_
    ) external returns (IVeloVault vault, uint256 nft);
}
