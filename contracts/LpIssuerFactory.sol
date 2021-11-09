// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./LpIssuer.sol";

contract LpIssuerVaultFactory is IVaultFactory {
    IVaultGovernance public vaultGovernance;

    constructor(IVaultGovernance vaultGovernance_) {
        vaultGovernance = vaultGovernance_;
    }

    /// @inheritdoc IVaultFactory
    function deployVault(address[] memory vaultTokens, bytes memory options) external returns (IVault) {
        require(msg.sender == address(vaultGovernance), "VG");
        (string memory name, string memory symbol) = abi.decode(options, (string, string));
        LpIssuer vault = new LpIssuer(vaultGovernance, vaultTokens, name, symbol);
        return IVault(address(vault));
    }
}
