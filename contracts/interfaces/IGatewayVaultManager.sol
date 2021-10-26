// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultManager.sol";

interface IGatewayVaultManager {
    /// @notice Nft of the gateway vault that owns the subvault nft
    /// @param nft Nft of the subvault to check
    /// @return The nft of the Gateway vault
    function vaultOwnerNft(uint256 nft) external view returns (uint256);

    /// @notice Address of the gateway vault that owns the subvault nft
    /// @param nft Nft of the subvault to check
    /// @return The address of the Gateway vault
    function vaultOwner(uint256 nft) external view returns (address);
}
