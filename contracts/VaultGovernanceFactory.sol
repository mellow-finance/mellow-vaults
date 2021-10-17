// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./libraries/Common.sol";

import "./interfaces/IVaultGovernanceFactory.sol";
import "./interfaces/IVaultGovernance.sol";
import "./VaultGovernance.sol";

contract VaultGovernanceFactory {
    function deployVaultGovernance(
        address[] memory tokens,
        IVaultManager manager,
        address treasury,
        address admin
    ) external returns (IVaultGovernance) {
        require(treasury != address(0), "TZA");
        require(admin != address(0), "AZA");
        VaultGovernance vaultGovernance = new VaultGovernance(
            tokens,
            manager,
            treasury,
            admin
        );
        return IVaultGovernance(vaultGovernance);
    }
}
