// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import "../external/aave/ILendingPool.sol";
import "./IAaveVault.sol";
import "./IVaultGovernance.sol";

interface IAaveVaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param lendingPool Reference to Aave LendingPool
    /// @param estimatedAaveAPY APY estimation for calulating tvl range. Measured in CommonLibrary.DENOMINATOR
    struct DelayedProtocolParams {
        ILendingPool lendingPool;
        uint256 estimatedAaveAPY;
    }

    /// @notice Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function delayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Delayed Protocol Params staged for commit after delay.
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Stage Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedProtocolParamsTimestamp.
    /// @param params New params
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external;

    /// @notice Commit Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function commitDelayedProtocolParams() external;

    /// @notice Deploys a new vault.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param owner_ Owner of the vault NFT
    function createVault(
        address[] memory vaultTokens_,
        address owner_
    ) external returns (IAaveVault vault, uint256 nft);
}
