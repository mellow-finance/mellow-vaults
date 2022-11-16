// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IMellowVault.sol";
import "../interfaces/vaults/IMellowVaultGovernance.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all Mellow Vaults params and can deploy a new Mellow Vault.
contract MellowVaultGovernance is ContractMeta, IMellowVaultGovernance, VaultGovernance {
    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("MellowVaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IMellowVaultGovernance
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        IERC20RootVault underlyingVault
    ) external returns (IMellowVault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = IMellowVault(vaddr);
        vault.initialize(nft, vaultTokens_, underlyingVault);
        emit DeployedVault(tx.origin, msg.sender, vaultTokens_, "", owner_, vaddr, nft);
    }
}
