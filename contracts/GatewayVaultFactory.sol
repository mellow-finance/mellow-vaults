// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./GatewayVault.sol";

contract GatewayVaultFactory {
    function deployVault(
        IVaultGovernance vaultGovernance,
        bytes calldata options
    ) external returns (IVault) {
        address[] memory tokens;
        address[] memory vaults;
        (tokens, vaults) = abi.decode(options, (address[], address[]));
        GatewayVault gatewayVault = new GatewayVault(vaultGovernance, tokens, vaults);
        return IVault(gatewayVault);
    }
}
