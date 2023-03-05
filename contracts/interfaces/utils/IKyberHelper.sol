// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../external/kyber/IPool.sol";
import "../external/kyber/IFactory.sol";
import "../external/kyber/periphery/IBasePositionManager.sol";

interface IKyberHelper {
    function liquidityToTokenAmounts(
        uint128 liquidity,
        IPool pool,
        uint256 kyberNft
    ) external view returns (uint256[] memory tokenAmounts);

    function tokenAmountsToLiquidity(
        uint256[] memory tokenAmounts,
        IPool pool,
        uint256 kyberNft
    ) external view returns (uint128 liquidity);

    function tokenAmountsToMaximalLiquidity(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) external pure returns (uint128 liquidity);

    function calculateTvlBySqrtPriceX96(
        IPool pool,
        uint256 kyberNft,
        uint160 sqrtPriceX96
    ) external view returns (uint256[] memory tokenAmounts);

    function calcTvl() external view returns (uint256[] memory minTokenAmounts, uint256[] memory maxTokenAmounts);

    function toAddress(bytes memory _bytes, uint256 _start) external pure returns (address);

}
