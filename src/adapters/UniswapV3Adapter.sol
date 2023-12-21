// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IAdapter.sol";

import "../interfaces/vaults/IUniV3Vault.sol";

import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/TickMath.sol";

contract UniswapV3Adapter is IAdapter {
    using SafeERC20 for IERC20;

    struct SecurityParams {
        uint16[] observationAgos;
        uint256 deviationMultiplierX96;
    }

    INonfungiblePositionManager public immutable positionManager;

    constructor(INonfungiblePositionManager positionManager_) {
        positionManager = positionManager_;
    }

    function mintWithDust(
        address poolAddress,
        int24 tickLower,
        int24 tickUpper,
        address recipient
    ) external returns (uint256 tokenId_) {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            1
        );

        IERC20(pool.token0()).safeIncreaseAllowance(address(positionManager), amount0);
        IERC20(pool.token1()).safeIncreaseAllowance(address(positionManager), amount1);

        (tokenId_, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: pool.token0(),
                token1: pool.token1(),
                fee: pool.fee(),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: type(uint256).max,
                recipient: recipient
            })
        );
    }

    function swapNft(
        address from,
        address vault,
        uint256 newNft
    ) external returns (uint256 oldNft) {
        oldNft = IUniV3Vault(vault).uniV3Nft();
        positionManager.safeTransferFrom(from, vault, newNft);
        if (oldNft != 0) {
            positionManager.burn(oldNft);
        }
    }

    function compound(address vault) external {
        IUniV3Vault(vault).collectEarnings();
    }

    function positionInfo(uint256 tokenId_)
        external
        view
        returns (
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity
        )
    {
        (, , , , , tickLower, tickUpper, liquidity, , , , ) = positionManager.positions(tokenId_);
    }

    function tokenId(address vault) external view returns (uint256) {
        return IUniV3Vault(vault).uniV3Nft();
    }

    function slot0EnsureNoMEV(address poolAddress, bytes memory securityParams)
        external
        view
        returns (uint160 sqrtPriceX96, int24 spotTick)
    {
        (sqrtPriceX96, spotTick, , , , , ) = IUniswapV3Pool(poolAddress).slot0();
        if (securityParams.length > 0) {
            // TODO: add mev checks
            // check in different ways
        }
    }

    function slot0(address poolAddress) external view returns (uint160 sqrtPriceX96, int24 spotTick) {
        (sqrtPriceX96, spotTick, , , , , ) = IUniswapV3Pool(poolAddress).slot0();
    }
}
