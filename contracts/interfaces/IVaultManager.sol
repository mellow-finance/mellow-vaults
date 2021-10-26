// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IProtocolGovernance.sol";
import "./IVaultManagerGovernance.sol";
import "./IVaultGovernanceOld.sol";

interface IVaultManager is IERC721, IVaultManagerGovernance {
    /// @notice Nft for the vault in the VaultManager
    /// @param vault Address of the vault
    /// @return Nft of the vault
    function nftForVault(address vault) external view returns (uint256);

    /// @notice Address of the vault by nft in the VaultManager
    /// @param nft Nft of the vault in the VaultManager
    /// @return Address of the Vault
    function vaultForNft(uint256 nft) external view returns (address);

    /// @notice Create a new Vault and VaultGovernance
    /// @param tokens A set of tokens that will be managed by the Vault
    /// @param strategyTreasury Strategy treasury address that will be used to collect Strategy Performance Fee
    /// @param admin Admin of the Vault
    /// @param options Deployment options (varies between vault managers)
    /// @return vaultGovernance The address of the depoyed VaultGovernance
    /// @return vault The address of the depoyed Vault
    /// @return nft The nft of the depoyed Vault in the VaultManager
    function createVault(
        address[] calldata tokens,
        address strategyTreasury,
        address admin,
        bytes memory options
    )
        external
        returns (
            IVaultGovernanceOld vaultGovernance,
            IVault vault,
            uint256 nft
        );

    event CreateVault(address vaultGovernance, address vault, uint256 nft, address[] tokens, bytes options);
}
