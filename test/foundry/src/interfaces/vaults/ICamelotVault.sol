// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./IIntegrationVault.sol";
import "./ICamelotVaultGovernance.sol";

import "../external/algebrav2/IAlgebraNonfungiblePositionManager.sol";
import "../external/algebrav2/IAlgebraFactory.sol";
import "../external/algebrav2/IAlgebraPool.sol";

import "../utils/ICamelotHelper.sol";

interface ICamelotVault is IERC721Receiver, IIntegrationVault {
    /// @dev nft of position in algebra pool
    function positionNft() external view returns (uint256);

    /// @dev address of erc20Vault
    function erc20Vault() external view returns (address);

    /// @dev position manager for positions in algebra pools
    function positionManager() external view returns (IAlgebraNonfungiblePositionManager);

    /// @dev pool factory for algebra pools
    function factory() external view returns (IAlgebraFactory);

    /// @dev helper contract for CamelotVault
    function helper() external view returns (ICamelotHelper);

    /// @dev Algebra Pool
    function pool() external view returns (IAlgebraPool);

    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    function initialize(
        uint256 nft_,
        address erc20Vault,
        address[] memory vaultTokens_
    ) external;

    /// @return collectedFees array of length 2 with amounts of collected and transferred fees from Camelot position to ERC20Vault
    function collectEarnings() external returns (uint256[] memory collectedFees);
}
