// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.0;

import "../interfaces/vaults/ICamelotVaultGovernance.sol";
import "../interfaces/vaults/ICamelotVault.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all Camelot Vaults params and can deploy a new Camelot Vault.
contract CamelotVaultGovernance is ContractMeta, ICamelotVaultGovernance, VaultGovernance {
    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || type(ICamelotVaultGovernance).interfaceId == interfaceId;
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc ICamelotVaultGovernance
    function createVault(
        address[] memory vaultTokens_,
        address owner_,
        address erc20Vault_
    ) external returns (ICamelotVault vault, uint256 nft) {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = ICamelotVault(vaddr);
        vault.initialize(nft, erc20Vault_, vaultTokens_);
        emit DeployedVault(tx.origin, msg.sender, vaultTokens_, abi.encode(erc20Vault_), owner_, vaddr, nft);
    }

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("CamelotVaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }
}
