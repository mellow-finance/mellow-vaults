// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./GatewayVault.sol";

contract GatewayVaultFactory {
    function deployVault(IVaultGovernance vaultGovernance, address[] calldata tokens) external returns (IVault) {
        GatewayVault gatewayVault = new GatewayVault(vaultGovernance, tokens);
        return IVault(gatewayVault);
    }
}
