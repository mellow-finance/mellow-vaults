// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./UniV3Vault.sol";

contract UniV3VaultFactory is IVaultFactory {
    function deployVault(
        IVaultGovernance vaultGovernance,
        bytes calldata options
    ) external returns (IVault) {
        address[] memory vaultTokens;
        uint24 fee;
        (vaultTokens, fee) = abi.decode(options, (address[], uint24));
        UniV3Vault vault = new UniV3Vault(vaultGovernance, vaultTokens, uint24(fee));
        return IVault(vault);
    }
}
