// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./GatewayVaultManager.sol";
import "./GatewayVault.sol";

contract GatewayVaultFactory is IVaultFactory {
    function deployVault(IVaultGovernance vaultGovernance, bytes memory options) external override returns (IVault) {
        uint256 len;
        assembly {
            len := mload(options)
        }
        uint256 vaultsCount = len / 32;
        address[] memory vaults = new address[](vaultsCount);
        for (uint256 i = 0; i < vaultsCount; ++i) {
            address vault;
            assembly {
                vault := mload(add(add(options, 0x20), mul(i, 0x20)))
            }
            vaults[i] = vault;
        }
        GatewayVault gatewayVault = new GatewayVault(vaultGovernance, vaults);
        return IVault(gatewayVault);
    }
}
