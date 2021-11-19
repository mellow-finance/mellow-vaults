// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./UniV3Vault.sol";

/// @notice Helper contract for UniV3VaultGovernance that can create new UniV3 Vaults.
contract UniV3VaultFactory is IVaultFactory {
    IVaultGovernance public vaultGovernance;

    /// @notice Creates a new contract.
    /// @param vaultGovernance_ Reference to VaultGovernance of this VaultKind
    constructor(IVaultGovernance vaultGovernance_) {
        vaultGovernance = vaultGovernance_;
    }

    /// @notice Deploy a new vault.
    /// @param vaultTokens ERC20 tokens under vault management
    /// @param options Should equal UniV3 pool fee
    function deployVault(address[] memory vaultTokens, bytes memory options) external returns (IVault) {
        require(msg.sender == address(vaultGovernance), "VG");
        uint256 fee = abi.decode(options, (uint256));
        UniV3Vault vault = new UniV3Vault(vaultGovernance, vaultTokens, uint24(fee));
        return IVault(vault);
    }
}
