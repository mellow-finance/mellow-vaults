// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IVaultRoot {
    function hasSubvault(address vault) external view returns (bool);
}

