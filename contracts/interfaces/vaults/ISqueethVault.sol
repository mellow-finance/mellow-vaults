// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";

interface ISqueethVault is IIntegrationVault {
    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    function initialize(uint256 nft_, address[] memory vaultTokens_, bool isShortPosition_) external;
}