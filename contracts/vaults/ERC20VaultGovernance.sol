// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IERC20VaultGovernance.sol";
import "../interfaces/vaults/IERC20Vault.sol";
import "../interfaces/vaults/IERC20VaultGovernance.sol";
import "./VaultGovernance.sol";
import "../utils/ContractMeta.sol";

/// @notice Governance that manages all ERC20 Vaults params and can deploy a new ERC20 Vault.
contract ERC20VaultGovernance is ContractMeta, IERC20VaultGovernance, VaultGovernance {
    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    // -------------------  INTERNAL, VIEW  -------------------

    function _contractName() internal pure override returns (bytes32) {
        return bytes32("ERC20VaultGovernance");
    }

    function _contractVersion() internal pure override returns (bytes32) {
        return bytes32("1.0.0");
    }

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @inheritdoc IERC20VaultGovernance
    function createVault(address[] memory vaultTokens_, address owner_)
        external
        returns (IERC20Vault vault, uint256 nft)
    {
        address vaddr;
        (vaddr, nft) = _createVault(owner_);
        vault = IERC20Vault(vaddr);
        vault.initialize(nft, vaultTokens_);
        emit DeployedVault(tx.origin, msg.sender, vaultTokens_, "", owner_, vaddr, nft);
    }
}
