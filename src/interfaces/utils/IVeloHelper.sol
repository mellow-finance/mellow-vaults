// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../external/velo/ICLPool.sol";
import "../external/velo/ICLFactory.sol";
import "../external/velo/INonfungiblePositionManager.sol";

interface IVeloHelper {
    function positionManager() external view returns (INonfungiblePositionManager);

    function liquidityToTokenAmounts(
        uint128 liquidity,
        ICLPool pool,
        uint256 tokenId
    ) external view returns (uint256[] memory tokenAmounts);

    function tokenAmountsToLiquidity(
        uint256[] memory tokenAmounts,
        ICLPool pool,
        uint256 tokenId
    ) external view returns (uint128 liquidity);

    function tokenAmountsToMaximalLiquidity(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) external pure returns (uint128 liquidity);

    function calculateTvlBySpotPrice(uint256 tokenId) external view returns (uint256[] memory);
}
