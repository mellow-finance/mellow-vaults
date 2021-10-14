// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/external/univ3/INonfungiblePositionManager.sol";
import "./interfaces/IVaultFactory.sol";
import "./VaultManager.sol";
import "./UniV3Vault.sol";

contract UniV3VaultFactory is IVaultFactory {
    function deployVault(IVaultGovernance vaultGovernance, bytes calldata options) external override returns (IVault) {
        uint256 fee = abi.decode(options, (uint256));
        UniV3Vault vault = new UniV3Vault(vaultGovernance, uint24(fee));
        return IVault(vault);
    }
}
