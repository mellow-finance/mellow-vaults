// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "../external/squeeth/IController.sol";
import "../external/univ3/ISwapRouter.sol";
import "./ISqueethVault.sol";
import "./IVaultGovernance.sol";
import "../oracles/IOracle.sol";

interface ISqueethVaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param controller Squeeth protocol Controller, which is used to mint/burn oSQTH, manage positions and etc
    /// @param router UniswapV3 SwapRouter contracts, which is used to perform swaps in the oSQTH/WETH pool
    struct DelayedProtocolParams {
        IController controller;
        ISwapRouter router;
        uint256 slippageD9;
        uint32 twapPeriod;
        address wethBorrowPool;
        IOracle oracle;
        address squeethHelper;
        uint256 maxDepegD9;
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
    function createVault(address owner_)
        external
        returns (ISqueethVault vault, uint256 nft);
}
