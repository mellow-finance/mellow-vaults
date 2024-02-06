// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../external/velo/ICLPool.sol";
import "../external/velo/ICLFactory.sol";
import "../external/velo/INonfungiblePositionManager.sol";

/// @notice Interface for the Velodrome Helper contract.
/// This contract provides various utility functions for working with Velodrome protocol components.
interface IVeloHelper {
    /// @notice Get the reference to the Velodrome Nonfungible Position Manager (NPM).
    /// @return INonfungiblePositionManager address of the Velodrome Nonfungible Position Manager.
    function positionManager() external view returns (INonfungiblePositionManager);

    /// @notice Calculate token amounts corresponding to liquidity based on the provided liquidity, Velodrome pool, and tokenId.
    /// @param liquidity The liquidity to convert to token amounts.
    /// @param pool The Velodrome AMM pool.
    /// @param tokenId The ID of the position.
    /// @return tokenAmounts Token amounts corresponding to the provided liquidity.
    function liquidityToTokenAmounts(
        uint128 liquidity,
        ICLPool pool,
        uint256 tokenId
    ) external view returns (uint256[] memory tokenAmounts);

    /// @notice Calculate liquidity corresponding to token amounts based on the provided token amounts, Velodrome pool, and tokenId.
    /// @param tokenAmounts The token amounts to convert to liquidity.
    /// @param pool The Velodrome AMM pool.
    /// @param tokenId The ID of the position.
    /// @return liquidity Liquidity corresponding to the provided token amounts.
    function tokenAmountsToLiquidity(
        uint256[] memory tokenAmounts,
        ICLPool pool,
        uint256 tokenId
    ) external view returns (uint128 liquidity);

    /// @notice Calculate maximal liquidity based on the provided parameters.
    /// @param sqrtRatioX96 The square root of the price ratio, scaled by 2^96.
    /// @param tickLower The lower tick of the position.
    /// @param tickUpper The upper tick of the position.
    /// @param amount0 The amount of token0.
    /// @param amount1 The amount of token1.
    /// @return liquidity Maximal liquidity calculated based on the provided parameters.
    function tokenAmountsToMaximalLiquidity(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) external pure returns (uint128 liquidity);

    /// @notice Calculate the total value locked for a given tokenId based on the spot price.
    /// @param tokenId The ID of the position.
    /// @return An array containing token amounts representing TVL.
    function calculateTvlBySpotPrice(uint256 tokenId) external view returns (uint256[] memory);
}
