// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IUniV3Vault is IERC721Receiver, IIntegrationVault {
    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param fee_ Fee of the UniV3 pool
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        uint24 fee_
    ) external;
}
