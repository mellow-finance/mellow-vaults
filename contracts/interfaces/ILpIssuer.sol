// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVault.sol";

interface ILpIssuer {
    /// @notice VaultRegistry NFT for this vault
    function nft() external view returns (uint256);

    /// @notice Nft of the underlying vault.
    function subvaultNft() external view returns (uint256);

    /// @notice Adds subvault nft to the vault.
    /// @dev Can be called only once.
    /// @param nft Subvault nft to add
    function addSubvault(uint256 nft) external;

    /// @notice Initialize contract with vault nft
    /// @param nft VaultRegistry NFT for this vault
    function initialize(uint256 nft) external;
}
