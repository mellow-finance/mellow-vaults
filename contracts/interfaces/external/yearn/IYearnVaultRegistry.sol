// SPDX-License-Identifier: MIT
pragma solidity =0.8.9;

interface IYearnVaultRegistry {
    function latestVault(address vault) external returns (address);
}
