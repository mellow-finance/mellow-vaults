// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../oracles/IOracle.sol";
import "./IERC20RootVault.sol";
import "./IVaultGovernance.sol";

interface IERC20RootVaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @param strategyTreasury Reference to address that will collect strategy management fees
    /// @param strategyPerformanceTreasury Reference to address that will collect strategy performance fees
    /// @param privateVault If true, only whitlisted depositors can deposit into the vault
    /// @param managementFee Management fee for Strategist denominated in 10 ** 9
    /// @param performanceFee Performance fee for Strategist denominated in 10 ** 9
    /// @param depositCallbackAddress Address of callback function after deposit
    /// @param withdrawCallbackAddress Address of callback function after withdraw
    struct DelayedStrategyParams {
        address strategyTreasury;
        address strategyPerformanceTreasury;
        bool privateVault;
        uint256 managementFee;
        uint256 performanceFee;
        address depositCallbackAddress;
        address withdrawCallbackAddress;
    }

    /// @notice Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param managementFeeChargeDelay The minimal interval between management fee charges
    /// @param oracle Oracle for getting token prices
    struct DelayedProtocolParams {
        uint256 managementFeeChargeDelay;
        IOracle oracle;
    }

    /// @notice Params that could be changed by Strategy or Protocol Governance.
    /// @param tokenLimitPerAddress Max LP token limit per address
    /// @param tokenLimit Max LP token for the vault
    struct StrategyParams {
        uint256 tokenLimitPerAddress;
        uint256 tokenLimit;
    }

    /// @notice Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param protocolFee Management fee for Protocol denominated in 10 ** 9
    struct DelayedProtocolPerVaultParams {
        uint256 protocolFee;
    }

    /// @notice Params that could be changed by Operator role of Protocol Governance.
    /// @param disableDeposit Disable deposit for all ERC20 vaults
    struct OperatorParams {
        bool disableDeposit;
    }

    /// @notice Number of maximum protocol fee
    function MAX_PROTOCOL_FEE() external view returns (uint256);

    /// @notice Number of maximum management fee
    function MAX_MANAGEMENT_FEE() external view returns (uint256);

    /// @notice Number of maximum performance fee
    function MAX_PERFORMANCE_FEE() external view returns (uint256);

    /// @notice Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function delayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Delayed Protocol Params staged for commit after delay.
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory);

    /// @notice Delayed Protocol Per Vault Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param nft VaultRegistry NFT of the vault
    function delayedProtocolPerVaultParams(uint256 nft) external view returns (DelayedProtocolPerVaultParams memory);

    /// @notice Delayed Protocol Per Vault Params staged for commit after delay.
    /// @param nft VaultRegistry NFT of the vault
    function stagedDelayedProtocolPerVaultParams(uint256 nft)
        external
        view
        returns (DelayedProtocolPerVaultParams memory);

    /// @notice Strategy Params.
    /// @param nft VaultRegistry NFT of the vault
    function strategyParams(uint256 nft) external view returns (StrategyParams memory);

    /// @notice Operator Params.
    function operatorParams() external view returns (OperatorParams memory);

    /// @notice Delayed Strategy Params
    /// @param nft VaultRegistry NFT of the vault
    function delayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory);

    /// @notice Delayed Strategy Params staged for commit after delay.
    /// @param nft VaultRegistry NFT of the vault
    function stagedDelayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory);

    /// @notice Set Strategy params, i.e. Params that could be changed by Strategy or Protocol Governance immediately.
    /// @param nft Nft of the vault
    /// @param params New params
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external;

    /// @notice Set Operator params, i.e. Params that could be changed by Operator or Protocol Governance immediately.
    /// @param params New params
    function setOperatorParams(OperatorParams calldata params) external;

    /// @notice Stage Delayed Protocol Per Vault Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params
    function stageDelayedProtocolPerVaultParams(uint256 nft, DelayedProtocolPerVaultParams calldata params) external;

    /// @notice Commit Delayed Protocol Per Vault Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedProtocolPerVaultParamsTimestamp
    /// @param nft VaultRegistry NFT of the vault
    function commitDelayedProtocolPerVaultParams(uint256 nft) external;

    /// @notice Stage Delayed Strategy Params, i.e. Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params
    function stageDelayedStrategyParams(uint256 nft, DelayedStrategyParams calldata params) external;

    /// @notice Commit Delayed Strategy Params, i.e. Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedStrategyParamsTimestamp
    /// @param nft VaultRegistry NFT of the vault
    function commitDelayedStrategyParams(uint256 nft) external;

    /// @notice Stage Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    /// @dev Can only be called after delayedProtocolParamsTimestamp.
    /// @param params New params
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external;

    /// @notice Commit Delayed Protocol Params, i.e. Params that could be changed by Protocol Governance with Protocol Governance delay.
    function commitDelayedProtocolParams() external;

    /// @notice Deploys a new vault.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param strategy_ The address that will have approvals for subvaultNfts
    /// @param subvaultNfts_ The NFTs of the subvaults that will be aggregated by this ERC20RootVault
    /// @param owner_ Owner of the vault NFT
    function createVault(
        address[] memory vaultTokens_,
        address strategy_,
        uint256[] memory subvaultNfts_,
        address owner_
    ) external returns (IERC20RootVault vault, uint256 nft);
}
