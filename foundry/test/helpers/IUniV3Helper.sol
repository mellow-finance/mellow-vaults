// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "./IUniswapV3Pool.sol";
import "./INonfungiblePositionManager.sol";

interface IUniV3Helper {
    function liquidityToTokenAmounts(
        uint128 liquidity,
        IUniswapV3Pool pool,
        uint256 uniV3Nft,
        INonfungiblePositionManager positionManager
    ) external view returns (uint256[] memory tokenAmounts);

    function tokenAmountsToLiquidity(
        uint256[] memory tokenAmounts,
        IUniswapV3Pool pool,
        uint256 uniV3Nft,
        INonfungiblePositionManager positionManager
    ) external view returns (uint128 liquidity);
    
    function calculatePositionInfo(
        INonfungiblePositionManager positionManager,
        IUniswapV3Pool pool,
        uint256 uniV3Nft
    )
        external
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}
