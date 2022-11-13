// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IERC20RootVault.sol";
import "./IIntegrationVault.sol";

interface IMellowVault is IIntegrationVault {
    /// @notice Reference to mellow root vault
    function vault() external view returns (IERC20RootVault);

    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param rootVault_ Reference to mellow root vault
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        IERC20RootVault rootVault_
    ) external;
}
