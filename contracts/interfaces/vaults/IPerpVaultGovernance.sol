// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "../external/perp/IPerpInternalVault.sol";
import "../external/perp/IClearingHouse.sol";
import "../external/perp/IAccountBalance.sol";
import "./IPerpFuturesVault.sol";
import "./IVaultGovernance.sol";

interface IPerpVaultGovernance is IVaultGovernance {

    struct DelayedProtocolParams {
        IPerpInternalVault vault;
        IClearingHouse clearingHouse;
        IAccountBalance accountBalance;
        address vusdcAddress;
        address usdcAddress;
        address uniV3FactoryAddress;
        uint256 maxProtocolLeverage;
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
    function createVault(address owner_, address baseToken_, uint256 leverageMultiplierD_, bool isLongBaseToken_)
        external
        returns (IPerpFuturesVault vault, uint256 nft);
}