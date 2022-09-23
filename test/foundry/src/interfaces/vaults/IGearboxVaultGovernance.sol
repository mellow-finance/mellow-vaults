// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "./IGearboxVault.sol";
import "./IVaultGovernance.sol";

interface IGearboxVaultGovernance is IVaultGovernance {

    struct DelayedProtocolParams {
        uint256 withdrawDelay;
        uint16 referralCode;
        address univ3Adapter;
        address crv;
        address cvx;
        uint256 minSlippageD;
    }

    struct DelayedProtocolPerVaultParams {
        address primaryToken;
        address curveAdapter;
        address convexAdapter;
        address facade;
        uint256 initialMarginalValue;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function delayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Delayed Protocol Params staged for commit after delay.
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory);

    function stagedDelayedProtocolPerVaultParams(uint256 nft)
        external
        view
        returns (DelayedProtocolPerVaultParams memory);

    function delayedProtocolPerVaultParams(uint256 nft) external view returns (DelayedProtocolPerVaultParams memory);

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Stage Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedProtocolParamsTimestamp.
    /// @param params New params
    function stageDelayedProtocolParams(DelayedProtocolParams memory params) external;

    /// @notice Commit Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function commitDelayedProtocolParams() external;

    function stageDelayedProtocolPerVaultParams(uint256 nft, DelayedProtocolPerVaultParams calldata params) external;

    function commitDelayedProtocolPerVaultParams(uint256 nft) external;


    function createVault(address[] memory vaultTokens_, address owner_)
        external
        returns (IGearboxVault vault, uint256 nft);
}