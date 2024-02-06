// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./IVeloVaultGovernance.sol";
import "./IIntegrationVault.sol";

import "../external/velo/INonfungiblePositionManager.sol";
import "../external/velo/ICLPool.sol";

import "../utils/IVeloHelper.sol";

/**
 * @notice Interface for the Velodrome Vault contract. This contract is responsible for managing ERC20 tokens in the Velodrome V2 protocol.
 * It interacts with Velodrome protocol components and allows users to deposit, withdraw, and collect rewards.
 */
interface IVeloVault is IERC721Receiver, IIntegrationVault {
    /// @notice Reference to the Velodrome Nonfungible Position Manager.
    /// @return INonfungiblePositionManager Nonfungible Position Manager reference.
    function positionManager() external view returns (INonfungiblePositionManager);

    /// @notice Reference to the Velodrome pool (CLPool).
    /// @return ICLPool CLPool reference.
    function pool() external view returns (ICLPool);

    /// @notice NFT of the Velodrome position manager associated with this Vault.
    /// @return uint256 associated NFT ID.
    function tokenId() external view returns (uint256);

    /// @notice Address of the helper contract for Velodrome arithmetic with ticks.
    /// @return IVeloHelper address of the helper contract.
    function helper() external view returns (IVeloHelper);

    /// @notice View function that returns strategy parameters for this Vault from VeloVaultGovernance.
    /// @return strategyParams The strategy parameters.
    function strategyParams() external view returns (IVeloVaultGovernance.StrategyParams memory);

    /// @notice Returns token amounts corresponding to liquidity based on the current Velodrome position.
    /// @param liquidity Liquidity that will be converted to token amounts.
    /// @return tokenAmounts Token amounts for the specified liquidity.
    function liquidityToTokenAmounts(uint128 liquidity) external view returns (uint256[] memory tokenAmounts);

    /// @notice Returns liquidity corresponding to token amounts based on the current Velodrome position.
    /// @param tokenAmounts Token amounts that will be converted to liquidity.
    /// @return liquidity Liquidity for the specified token amounts.
    function tokenAmountsToLiquidity(uint256[] memory tokenAmounts) external view returns (uint128 liquidity);

    /// @notice Initializes a new contract.
    /// Can only be initialized by Vault Governance.
    /// @param nft_ NFT of the vault in the Vault Registry.
    /// @param vaultTokens_ ERC20 tokens that will be managed by this Vault.
    /// @param tickSpacing_ CLPool tick spacing.
    function initialize(
        uint256 nft_,
        address[] memory vaultTokens_,
        int24 tickSpacing_
    ) external;

    /// @notice Collects rewards from the gauge and sends them to the farm and protocol treasury.
    /// @return farmRewards Amount of rewards sent to the farm.
    /// @return treasuryRewards Amount of rewards sent to the protocol treasury.
    function collectRewards() external returns (uint256 farmRewards, uint256 treasuryRewards);
}
