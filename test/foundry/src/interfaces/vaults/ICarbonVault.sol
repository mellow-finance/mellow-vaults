// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../external/carbon/contracts/carbon/interfaces/ICarbonController.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./IIntegrationVault.sol";

interface ICarbonVault is IERC721Receiver, IIntegrationVault {
    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    function initialize(uint256 nft_, address[] memory vaultTokens_) external;

    function addPosition(uint256 lowerPriceLOX96, uint256 startPriceLOX96, uint256 upperPriceLOX96, uint256 lowerPriceROX96, uint256 startPriceROX96, uint256 upperPriceROX96, uint256 amount0, uint256 amount1) external returns (uint256 nft);
    
    function closePosition(uint256 nft) external;

    function updatePosition(uint256 nft, uint256 amount0, uint256 amount1) external;

    function controller() external returns (ICarbonController);

    function tokensReversed() external returns (bool);

    function wethIndex() external returns (uint256);

    function weth() external returns (address);

    function getPosition(uint256 index) external returns (uint256 nft);

}
