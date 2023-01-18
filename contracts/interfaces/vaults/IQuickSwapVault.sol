// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./IIntegrationVault.sol";
import "./IQuickSwapVaultGovernance.sol";

import "../external/quickswap/INonfungiblePositionManager.sol";
import "../external/quickswap/IAlgebraEternalFarming.sol";
import "../external/quickswap/IAlgebraFactory.sol";
import "../external/quickswap/IFarmingCenter.sol";
import "../external/quickswap/ISwapRouter.sol";
import "../external/quickswap/IDragonLair.sol";

interface IQuickSwapVault is IERC721Receiver, IIntegrationVault {
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

    /// @param strategyParams mutable parameters of vault
    /// @param rewardTokenAmount amount of collected reward token
    /// @param bonusRewardTokenAmount amount of collected bonus reward token
    function collectRewards(IQuickSwapVaultGovernance.DelayedStrategyParams memory strategyParams)
        external
        returns (uint256 rewardTokenAmount, uint256 bonusRewardTokenAmount);

    /// @return params strategy params of the vault
    function delayedStrategyParams()
        public
        view
        returns (IQuickSwapVaultGovernance.DelayedStrategyParams memory params)
}
