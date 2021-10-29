// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./interfaces/IVaultFactory.sol";
import "./AaveVault.sol";

contract AaveVaultFactory is IVaultFactory {
    function deployVault(IVaultGovernance vaultGovernance, bytes calldata options) 
        external returns (IVault) {
        address[] memory vaultTokens = abi.decode(options, (address[]));
        AaveVault vault = new AaveVault(vaultGovernance, vaultTokens);
        return IVault(vault);
    }
}
