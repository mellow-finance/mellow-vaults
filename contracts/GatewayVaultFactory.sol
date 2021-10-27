// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./GatewayVaultManager.sol";
import "./GatewayVault.sol";

contract GatewayVaultFactory {
    function deployVault(
        IVaultGovernance vaultGovernance,
        address[] memory tokens,
        address[] memory vaults
    ) external returns (IVault) {
        GatewayVault gatewayVault = new GatewayVault(vaultGovernance, tokens, vaults);
        return IVault(gatewayVault);
    }
}
