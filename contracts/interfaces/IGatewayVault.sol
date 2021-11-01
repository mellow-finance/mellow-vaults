// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVault.sol";

interface IGatewayVault is IVault {
    /// @notice Checks that vault is subvault of the IGatewayVault
    /// @param vault The vault to check
    /// @return `true` if vault is a subvault of the IGatewayVault
    function hasSubvault(address vault) external view returns (bool);

    /// @notice Breakdown of tvls by subvault
    /// @return tokenAmounts Token amounts with subvault breakdown. If there are `k` subvaults then token `j`, `tokenAmounts[j]` would be a vector 1 x k - breakdown of token amount by subvaults.
    function vaultsTvl() external view returns (uint256[][] memory tokenAmounts);

    /// @notice A tvl of a specific subvault
    /// @param vaultNum The number of the subvault in the subvaults array.
    /// @return An array of token amounts (tvl) in the same order as vaultTokens.
    function vaultTvl(uint256 vaultNum) external view returns (uint256[] memory);

    /// @notice Accumulated earnings by subvault
    /// @param vaultNum The number of the subvault in the subvaults array.
    /// @return An array of token amounts (earnings) in the same order as vaultTokens.
    function vaultEarnings(uint256 vaultNum) external view returns (uint256[] memory);
}
