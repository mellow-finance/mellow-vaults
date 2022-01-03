// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../trader/interfaces/ITrader.sol";

interface IERC20Vault is ITrader, IIntegrationVault {
    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external;
}
