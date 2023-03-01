// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../external/kyber/periphery/IBasePositionManager.sol";
import "../external/kyber/IKyberSwapElasticLM.sol";
import "../oracles/IOracle.sol";
import "./IVaultGovernance.sol";
import "./IKyberVault.sol";

interface IKyberVaultGovernance is IVaultGovernance {

    struct DelayedProtocolParams {
        IBasePositionManager positionManager;
        IKyberSwapElasticLM farm;
        IOracle mellowOracle;
    }

    struct DelayedStrategyParams {
        bytes[] paths;
        uint256 pid;
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

    /// @notice Delayed Strategy Params
    /// @param nft VaultRegistry NFT of the vault
    function delayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory);

    /// @notice Delayed Strategy Params staged for commit after delay.
    /// @param nft VaultRegistry NFT of the vault
    function stagedDelayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory);

    /// @notice Stage Delayed Strategy Params, i.e. Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params
    function stageDelayedStrategyParams(uint256 nft, DelayedStrategyParams calldata params) external;

    /// @notice Commit Delayed Strategy Params, i.e. Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedStrategyParamsTimestamp
    /// @param nft VaultRegistry NFT of the vault
    function commitDelayedStrategyParams(uint256 nft) external;

    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        uint24 fee_,
        address kyberHelper_
    ) external returns (IKyberVault vault, uint256 nft);
}
