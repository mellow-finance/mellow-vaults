// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./GatewayVault.sol";

contract GatewayVaultFactory is IVaultFactory {
    IVaultGovernance public vaultGovernance;

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
