// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";

interface IAaveV3Vault is IIntegrationVault {
    /// @notice Update all tvls to current aToken balances.
    function updateTvls() external;

    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external;
}
