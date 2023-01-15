// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./IIntegrationVault.sol";
import "../external/quickswap/INonfungiblePositionManager.sol";

interface IQuickSwapVault is IERC721Receiver, IIntegrationVault {
    function positionManager() external view returns (INonfungiblePositionManager);
    function farmingNft() external view returns (uint256);
    function positionNft() external view returns (uint256);
    function quickSwapHepler() external view returns (address);

    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    /// @param fee_ Fee of the UniV3 pool
    /// @param uniV3Helper_ address of helper for UniV3 arithmetic with ticks
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        uint24 fee_,
        address uniV3Helper_
    ) external;
}
