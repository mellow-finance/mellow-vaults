// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVaultGovernance.sol";

interface IVaultFactory {
    function deployVaultGovernance(
        address[] memory tokens,
        IVaultManager manager,
        address treasury,
        address admin
    ) external returns (IVaultGovernance vaultGovernance);
}
