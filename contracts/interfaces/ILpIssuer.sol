// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVault.sol";

interface ILpIssuer {
    /// @notice Nft of the underlying vault.
    function subvaultNft() external view returns (uint256);

    /// @notice Adds subvault nft to the vault.
    /// @dev Can be called only once.
    /// @param nft Subvault nft to add
    function addSubvault(uint256 nft) external;
}
