// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/IVaultFactory.sol";
import "../interfaces/IVaultGovernance.sol";
import "./GatewayVaultTest.sol";
import "contracts/libraries/ExceptionsLibrary.sol";

contract GatewayVaultTestFactory is IVaultFactory {
    IVaultGovernance public vaultGovernance;

    constructor(IVaultGovernance vaultGovernance_) {
        vaultGovernance = vaultGovernance_;
    }

    function setVaultGovernance(address newVaultGovernance) public {
        vaultGovernance = IVaultGovernance(newVaultGovernance);
    }

    function deployVault(address[] memory vaultTokens, bytes memory) external returns (IVault) {
        require(msg.sender == address(vaultGovernance), ExceptionsLibrary.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE);
        GatewayVaultTest gatewayVault = new GatewayVaultTest(vaultGovernance, vaultTokens);
        return IVault(gatewayVault);
    }
}
