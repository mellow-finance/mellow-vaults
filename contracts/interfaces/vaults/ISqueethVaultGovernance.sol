// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "../external/squeeth/IController.sol";
import "../external/univ3/ISwapRouter.sol";
import "./ISqueethVault.sol";
import "./IVaultGovernance.sol";

interface ISqueethVaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Protocol Governance with Protocol Governance delay.
    struct DelayedProtocolParams {
        IController controller;
        ISwapRouter router;
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
    /// @param owner_ Owner of the vault NFT
    function createVault(address owner_, bool isShortPosition)
        external
        returns (ISqueethVault vault, uint256 nft);
}
