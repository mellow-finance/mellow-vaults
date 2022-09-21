// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "./IGearboxVault.sol";
import "./IVaultGovernance.sol";

interface IGearboxVaultGovernance is IVaultGovernance {

    struct DelayedProtocolParams {
        uint256 withdrawDelay;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function delayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Delayed Protocol Params staged for commit after delay.
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory);

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Stage Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedProtocolParamsTimestamp.
    /// @param params New params
    function stageDelayedProtocolParams(DelayedProtocolParams memory params) external;

    /// @notice Commit Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function commitDelayedProtocolParams() external;


    function createVault(address owner_, address primaryToken_, address depositToken_, address curveAdapter_, address convexAdapter_, address facade_, uint256 convexPoolId_, uint256 targetHealthFactorD_,
        bytes memory options)
        external
        returns (IGearboxVault vault, uint256 nft);
}