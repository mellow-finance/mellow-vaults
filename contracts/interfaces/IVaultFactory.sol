// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernance.sol";
import "./IVault.sol";

interface IVaultFactory {
    function deployVault(IVaultGovernance vaultGovernance, bytes calldata options) external returns (IVault vault);
}
