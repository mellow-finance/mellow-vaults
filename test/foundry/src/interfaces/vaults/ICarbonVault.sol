// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";

interface ICarbonVault is IIntegrationVault {
    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external;

    function addPosition(uint256 lowerPriceLOX96, uint256 upperPriceLOX96, uint256 startPriceLOX96, uint256 lowerPriceROX96, uint256 upperPriceROX96, uint256 startPriceROX96, uint256 amount0, uint256 amount1) external;

    function closePosition(uint256 nft) external;

    function updatePosition(uint256 nft, uint256 amount0, uint256 amount1) external;
}
