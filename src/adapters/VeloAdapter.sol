// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IAdapter.sol";

import "../interfaces/vaults/IVeloVault.sol";

import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/CommonLibrary.sol";

contract UniswapV3Adapter is IAdapter {
    using SafeERC20 for IERC20;

    struct SecurityParams {
        uint16[] observationAgos;
        uint256 deviationMultiplierX96;
    }

    uint256 public constant Q96 = 2**96;

    INonfungiblePositionManager public immutable positionManager;

    constructor(INonfungiblePositionManager positionManager_) {
        positionManager = positionManager_;
    }

    function mint(
        address poolAddress,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        address recipient
    ) external returns (uint256 tokenId_) {
        ICLPool pool = ICLPool(poolAddress);
        (uint160 sqrtRatioX96, , , , , ) = pool.slot0();

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );

        IERC20(pool.token0()).safeIncreaseAllowance(address(positionManager), amount0);
        IERC20(pool.token1()).safeIncreaseAllowance(address(positionManager), amount1);

        (tokenId_, , , ) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: pool.token0(),
                token1: pool.token1(),
                tickSpacing: pool.tickSpacing(),
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
        oldNft = IVeloVault(vault).tokenId();
        positionManager.safeTransferFrom(from, vault, newNft);
        if (oldNft != 0) {
            positionManager.burn(oldNft);
        }
    }

    function compound(address vault) external {
        IVeloVault(vault).collectRewards();
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
        return IVeloVault(vault).tokenId();
    }

    function slot0EnsureNoMEV(address poolAddress, bytes memory securityParams)
        external
        view
        returns (uint160 sqrtPriceX96, int24 spotTick)
    {
        uint16 observationIndex;
        uint16 observationCardinality;
        (sqrtPriceX96, spotTick, observationIndex, observationCardinality, , ) = ICLPool(poolAddress).slot0();
        if (securityParams.length == 0) return (sqrtPriceX96, spotTick);
        SecurityParams memory params = abi.decode(securityParams, (SecurityParams));
        int24[] memory observations = new int24[](params.observationAgos.length - 1);
        uint32 lastTimestamp;
        int56 lastCumulativeTick;
        for (uint256 i = 0; i <= observations.length; i++) {
            require(params.observationAgos[i] < observationCardinality, "Invalid index");

            uint256 index = (observationCardinality + observationIndex - params.observationAgos[i]) %
                observationCardinality;
            (uint32 timestamp, int56 tickCumulative, , bool initialized) = ICLPool(poolAddress).observations(index);
            require(initialized, "Invalid index");
            if (i > 0) {
                observations[i - 1] = int24(
                    (tickCumulative - lastCumulativeTick) / (int32(timestamp) - int32(lastTimestamp))
                );
            }
            lastTimestamp = timestamp;
            lastCumulativeTick = tickCumulative;
        }
        uint256[] memory deviations = new uint256[](observations.length - 1);
        for (uint256 i = 0; i < observations.length - 1; i++) {
            int56 deviation = observations[i + 1] - observations[i];
            if (deviation < 0) deviation = -deviation;
            deviations[i] = uint56(deviation);
        }
        uint256 median = CommonLibrary.getMedianValue(deviations);
        int24 maxDeviation = int24(int256(FullMath.mulDiv(median, params.deviationMultiplierX96, Q96)));
        for (uint256 i = 0; i < observations.length; i++) {
            int24 deviation = spotTick - observations[i];
            if (deviation < 0) deviation = -deviation;
            if (deviation > maxDeviation) revert("MEV detected");
        }
    }

    function slot0(address poolAddress) external view returns (uint160 sqrtPriceX96, int24 spotTick) {
        (sqrtPriceX96, spotTick, , , , ) = ICLPool(poolAddress).slot0();
    }
}
