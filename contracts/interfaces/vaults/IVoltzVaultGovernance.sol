// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "./IVaultGovernance.sol";
import "./IVoltzVault.sol";
import "../external/voltz/IPeriphery.sol";

interface IVoltzVaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Protocol Governance with Protocol Governance delay.
    struct DelayedProtocolParams {
        IPeriphery periphery;
    }

    /// @notice Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function delayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Delayed Protocol Params staged for commit after delay.
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Stage Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param params New params
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external;

    /// @notice Commit Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function commitDelayedProtocolParams() external;

    /// @notice Deploys a new vault.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param owner_ Owner of the vault NFT
    /// @param marginEngine_ margin engine address that the vault is created on top of
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        address marginEngine_,
        int24 initialTickLow,
        int24 initialTickHigh
    ) external returns (IVoltzVault vault, uint256 nft);
}
