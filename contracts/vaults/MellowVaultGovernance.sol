// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "../interfaces/vaults/IMellowVault.sol";
import "../interfaces/vaults/IMellowVaultGovernance.sol";
import "../libraries/ExceptionsLibrary.sol";
import "../utils/ContractMeta.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all Mellow Vaults params and can deploy a new Mellow Vault.
contract MellowVaultGovernance is ContractMeta, IMellowVaultGovernance, VaultGovernance {
    bytes32 public constant CONTRACT_NAME = "MellowVaultGovernance";
    bytes32 public constant CONTRACT_VERSION = "1.0.0";

    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    constructor(InternalParams memory internalParams_) VaultGovernance(internalParams_) {}

    // -------------------  EXTERNAL, VIEW  -------------------

    function CONTRACT_NAME_READABLE() external pure override returns (string memory) {
        return string(abi.encodePacked(CONTRACT_NAME));
    }

    function CONTRACT_VERSION_READABLE() external pure override returns (string memory) {
        return string(abi.encodePacked(CONTRACT_VERSION));
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
    }
}
