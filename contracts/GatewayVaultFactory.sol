// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./GatewayVaultManager.sol";
import "./GatewayVault.sol";

contract GatewayVaultFactory is IVaultFactory {
    function deployVault(IVaultGovernanceOld vaultGovernance, bytes memory options) external override returns (IVault) {
        address[] memory vaults = abi.decode(options, (address[]));
        GatewayVault gatewayVault = new GatewayVault(vaultGovernance, vaults);
        return IVault(gatewayVault);
    }
}
