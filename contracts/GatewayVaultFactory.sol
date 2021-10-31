// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./GatewayVault.sol";

contract GatewayVaultFactory {
    function deployVault(IVaultGovernance vaultGovernance, bytes calldata options) external returns (IVault) {
        address[] memory tokens = abi.decode(options, (address[]));
        GatewayVault gatewayVault = new GatewayVault(vaultGovernance, tokens);
        return IVault(gatewayVault);
    }
}
