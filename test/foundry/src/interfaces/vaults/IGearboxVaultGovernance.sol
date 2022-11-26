// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IGearboxVault.sol";
import "./IVaultGovernance.sol";

interface IGearboxVaultGovernance is IVaultGovernance {

    /// @notice Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @param crv3Pool 3CRV token address
    /// @param crv CRV token address
    /// @param cvx CVX token address
    /// @param maxSlippageD9 Maximal admissible slippage for swaps between primary/deposit tokes
    /// @param maxSmallPoolsSlippageD9 Maximal admissible slippage for swaps crv-weth and cvx-weth
    /// @param maxCurveSlippageD9 Maximal admissible slippage for add/remove liquidity in Curve pool
    /// @param uniswapRouter Address of the Uniswap V3 router
    struct DelayedProtocolParams {
        address crv3Pool;
        address crv;
        address cvx;
        uint256 maxSlippageD9;
        uint256 maxSmallPoolsSlippageD9;
        uint256 maxCurveSlippageD9;
        address uniswapRouter;
    }

    /// @notice Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param primaryToken Primary token of the vault (i.e. the token of the Gearbox Credit Account)
    /// @param univ3Adapter Address of the Uniswap V3 Adapter by Gearbox used by the system
    /// @param facade Address of the Gearbox CreditFacade contract used by the vault
    /// @param withdrawDelay The minimal time to pass between two consecutive withdrawal orders execution
    /// @param initialMarginalValueD9 Initial value of marginal factor of the vault
    /// @param referralCode The referral code to be used when depositing to Gearbox
    struct DelayedProtocolPerVaultParams {
        address primaryToken;
        address univ3Adapter;
        address facade;
        uint256 withdrawDelay;
        uint256 initialMarginalValueD9;
        uint16 referralCode;
    }

    /// @notice Params that could be changed by Strategy or Protocol Governance.
    /// @param largePoolFeeUsed Fee for the primary/deposit pool we want to use
    struct StrategyParams {
        uint24 largePoolFeeUsed;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function delayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Delayed Protocol Params staged for commit after delay.
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Delayed Protocol Per Vault Params staged for commit after delay.
    /// @param nft VaultRegistry NFT of the vault
    function stagedDelayedProtocolPerVaultParams(uint256 nft)
        external
        view
        returns (DelayedProtocolPerVaultParams memory);

    /// @notice Delayed Protocol Per Vault Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param nft VaultRegistry NFT of the vault
    function delayedProtocolPerVaultParams(uint256 nft) external view returns (DelayedProtocolPerVaultParams memory);

    /// @notice Strategy Params.
    function strategyParams(uint256 nft) external view returns (StrategyParams memory);

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Stage Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedProtocolParamsTimestamp.
    /// @param params New params
    function stageDelayedProtocolParams(DelayedProtocolParams memory params) external;

    /// @notice Commit Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function commitDelayedProtocolParams() external;

    /// @notice Stage Delayed Protocol Per Vault Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params
    function stageDelayedProtocolPerVaultParams(uint256 nft, DelayedProtocolPerVaultParams calldata params) external;

    /// @notice Commit Delayed Protocol Per Vault Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedProtocolPerVaultParamsTimestamp
    /// @param nft VaultRegistry NFT of the vault
    function commitDelayedProtocolPerVaultParams(uint256 nft) external;

    /// @notice Set Strategy params, i.e. Params that could be changed by Strategy or Protocol Governance immediately.
    /// @param params New params
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external;

    /// @notice Deploys a new vault.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param owner_ Owner of the vault NFT
    /// @param helper_ Gearbox helper contract address
    function createVault(address[] memory vaultTokens_, address owner_, address helper_)
        external
        returns (IGearboxVault vault, uint256 nft);
}