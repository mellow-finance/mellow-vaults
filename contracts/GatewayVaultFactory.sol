// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./GatewayVault.sol";

/// @notice Helper contract for GatewayVaultGovernance that can create new Gateway Vaults.
contract GatewayVaultFactory is IVaultFactory {
    IVaultGovernance public vaultGovernance;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance of this VaultKind
    constructor(IVaultGovernance vaultGovernance_) {
        vaultGovernance = vaultGovernance_;
    }

    /// @inheritdoc IVaultFactory
    function deployVault(address[] memory vaultTokens, bytes memory) external returns (IVault) {
        require(msg.sender == address(vaultGovernance), "VG");
        GatewayVault gatewayVault = new GatewayVault(vaultGovernance, vaultTokens);
        return IVault(gatewayVault);
    }
}
