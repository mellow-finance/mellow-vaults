// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernance.sol";

interface ILpIssuerVaultGovernance is IVaultGovernance {
    /// @notice Params that could be changed by Strategy or Protocol Governance with Protocol Governance delay
    /// @param tokenLimitPerAddress Reference to address that will collect strategy fees
    struct StrategyParams {
        uint256 tokenLimitPerAddress;
    }

    /// @notice Strategy Params
    /// @param nft VaultRegistry NFT of the vault
    function strategyParams(uint256 nft) external view returns (StrategyParams memory);

    /// @notice Set Strategy params, i.e. Params that could be changed by Strategy or Protocol Governance immediately
    /// @param nft Nft of the vault
    /// @param params New params
    function setStrategyParams(uint256 nft, StrategyParams calldata params) external;

    /// @notice Emitted when new StrategyParams are set
    /// @param origin Origin of the transaction
    /// @param sender Sender of the transaction
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params that are set
    event SetStrategyParams(address indexed origin, address indexed sender, uint256 indexed nft, StrategyParams params);
}
