// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "./external/univ3/INonfungiblePositionManager.sol";
import "./IVaultGovernance.sol";
import "./IMellowOracle.sol";
import "./IUniV3Vault.sol";

interface IUniV3VaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param positionManager Reference to UniV3 INonfungiblePositionManager
    struct DelayedProtocolParams {
        INonfungiblePositionManager positionManager;
        IMellowOracle oracle;
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
    /// @param fee_ Fee of the UniV3 pool
    /// @param owner_ Owner of the vault NFT
    function createVault(
        address[] memory vaultTokens_,
        uint24 fee_,
        address owner_
    ) external returns (IUniV3Vault vault, uint256 nft);
}
