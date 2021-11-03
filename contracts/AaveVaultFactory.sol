// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./AaveVault.sol";

contract AaveVaultFactory is IVaultFactory {
    IVaultGovernance public vaultGovernance;

    constructor(IVaultGovernance vaultGovernance_) {
        vaultGovernance = vaultGovernance_;
    }

    /// @inheritdoc IVaultFactory
    function deployVault(address[] memory vaultTokens, bytes memory) external returns (IVault) {
        require(msg.sender == address(vaultGovernance), "VG");
        AaveVault vault = new AaveVault(vaultGovernance, vaultTokens);
        return IVault(vault);
    }
}
