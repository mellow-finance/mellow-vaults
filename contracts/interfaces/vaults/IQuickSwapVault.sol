// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./IIntegrationVault.sol";
import "./IQuickSwapVaultGovernance.sol";

import "../external/quickswap/IAlgebraNonfungiblePositionManager.sol";
import "../external/quickswap/IAlgebraEternalFarming.sol";
import "../external/quickswap/IAlgebraFactory.sol";
import "../external/quickswap/IFarmingCenter.sol";
import "../external/quickswap/IAlgebraSwapRouter.sol";
import "../external/quickswap/IDragonLair.sol";

import "../utils/IQuickSwapHelper.sol";

interface IQuickSwapVault is IERC721Receiver, IIntegrationVault {
    /// @dev nft of position in algebra pool
    function positionNft() external view returns (uint256);

    /// @dev address of erc20Vault
    function erc20Vault() external view returns (address);

    /// @dev dragon-QUICK token address
    function dQuickToken() external view returns (address);

    /// @dev QUICK token address
    function quickToken() external view returns (address);

    /// @dev farming center contract
    function farmingCenter() external view returns (IFarmingCenter);

    /// @dev swap router to process swaps on algebra pools
    function swapRouter() external view returns (IAlgebraSwapRouter);

    /// @dev position manager for positions in algebra pools
    function positionManager() external view returns (IAlgebraNonfungiblePositionManager);

    /// @dev pool factory for algebra pools
    function factory() external view returns (IAlgebraFactory);

    /// @dev helper contract for QuickSwapVault
    function helper() external view returns (IQuickSwapHelper);

    /// @notice Initialized a new contract.
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault
    function initialize(
        uint256 nft_,
        address erc20Vault,
        address[] memory vaultTokens_
    ) external;

    /// @param nft nft position of quickswap protocol
    /// @param farmingCenter_ Algebra main farming contract. Manages farmings and performs entry, exit and other actions.
    function openFarmingPosition(uint256 nft, IFarmingCenter farmingCenter_) external;

    /// @param nft nft position of quickswap protocol
    /// @param farmingCenter_ Algebra main farming contract. Manages farmings and performs entry, exit and other actions.
    function burnFarmingPosition(uint256 nft, IFarmingCenter farmingCenter_) external;

    /// @return collectedFees array of length 2 with amounts of collected and transferred fees from Quickswap position to ERC20Vault
    function collectEarnings() external returns (uint256[] memory collectedFees);

    /// @param collectedRewards amount of collected tokes in underlying tokens
    function collectRewards() external returns (uint256[] memory collectedRewards);

    /// @return params strategy params of the vault
    function strategyParams()
        external
        view
        returns (IQuickSwapVaultGovernance.StrategyParams memory params);
}
