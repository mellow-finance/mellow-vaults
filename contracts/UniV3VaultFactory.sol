// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./interfaces/IVaultFactory.sol";
import "./VaultManager.sol";
import "./UniV3Vault.sol";

contract UniV3VaultFactory {
    function deployVault(
        IVaultGovernance vaultGovernance,
        address[] memory vaultTokens,
        uint24 fee
    ) external returns (IVault) {
        UniV3Vault vault = new UniV3Vault(vaultGovernance, vaultTokens, uint24(fee));
        return IVault(vault);
    }
}
