// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IProtocolGovernance.sol";
import "./IVaultRegistry.sol";
import "./IVaultFactory.sol";
import "./IVault.sol";

interface IVaultGovernance {
    /// @notice Internal references of the contract
    /// @param protocolGovernance Reference to Protocol Governance
    /// @param registry Reference to Vault Registry
    /// @param factory Factory for new vaults
    struct InternalParams {
        IProtocolGovernance protocolGovernance;
        IVaultRegistry registry;
        IVaultFactory factory;
    }

    // -------------------  PUBLIC, VIEW  -------------------

    /// @notice Timestamp in unix time seconds after which staged Delayed Strategy Params could be committed
    /// @param nft Nft of the vault
    function delayedStrategyParamsTimestamp(uint256 nft) external view returns (uint256);

    /// @notice Timestamp in unix time seconds after which staged Delayed Protocol Params could be committed
    function delayedProtocolParamsTimestamp() external view returns (uint256);

    /// @notice Timestamp in unix time seconds after which staged Internal Params could be committed
    function internalParamsTimestamp() external view returns (uint256);

    /// @notice Internal Params of the contract
    function internalParams() external view returns (InternalParams memory);

    /// @notice Staged new Internal Params
    /// @dev The Internal Params could be committed after internalParamsTimestamp
    function stagedInternalParams() external view returns (InternalParams memory);

    /// @notice Reference to Strategy Treasury address
    /// @param nft Nft of the vault
    function strategyTreasury(uint256 nft) external view returns (address);

    // -------------------  PUBLIC, MUTATING  -------------------

    /// @notice Deploy a new vault
    /// @param vaultTokens ERC20 tokens under vault management
    /// @param options Reserved additional deploy options. Should be 0x0.
    /// @param owner Owner of the registry vault nft
    /// @return vault Address of the new vault
    /// @return nft Nft of the vault in the vault registry
    function deployVault(
        address[] memory vaultTokens,
        bytes memory options,
        address owner
    ) external returns (IVault vault, uint256 nft);

    /// @notice Stage new Internal Params
    /// @param newParams New Internal Params
    function stageInternalParams(InternalParams memory newParams) external;

    /// @notice Commit staged Internal Params
    function commitInternalParams() external;

    event StagedInternalParams(address indexed origin, address indexed sender, InternalParams newParams, uint256 start);
    event CommitedInternalParams(address indexed origin, address indexed sender, InternalParams newParams);
}
