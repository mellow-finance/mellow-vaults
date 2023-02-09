// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../external/kyber/periphery/IBasePositionManager.sol";
import "../oracles/IOracle.sol";
import "./IVaultGovernance.sol";
import "./IKyberVault.sol";

interface IKyberVaultGovernance is IVaultGovernance {

    struct DelayedProtocolParams {
        IBasePositionManager positionManager;
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

    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        uint24 fee_,
        address kyberHelper_
    ) external returns (IKyberVault vault, uint256 nft);
}
