// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.9;

import "../interfaces/IVaultFactory.sol";
import "../interfaces/IVaultFactory.sol";
import "./AaveVaultTest.sol";
import "contracts/libraries/ExceptionsLibrary.sol";

contract AaveVaultTestFactory is IVaultFactory {
    IVaultGovernance public vaultGovernance;

    constructor(IVaultGovernance vaultGovernance_) {
        vaultGovernance = vaultGovernance_;
    }

    function setVaultGovernance(address newVaultGovernance) public {
        vaultGovernance = IVaultGovernance(newVaultGovernance);
    }

    function deployVault(address[] memory vaultTokens, bytes memory) external returns (IVault) {
        require(msg.sender == address(vaultGovernance), ExceptionsLibrary.SHOULD_BE_CALLED_BY_VAULT_GOVERNANCE);
        AaveVaultTest vault = new AaveVaultTest(vaultGovernance, vaultTokens);
        return IVault(vault);
    }
}
