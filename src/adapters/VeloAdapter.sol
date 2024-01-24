// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/adapters/IAdapter.sol";

import "../interfaces/vaults/IVeloVault.sol";

import "../libraries/external/LiquidityAmounts.sol";
import "../libraries/external/TickMath.sol";
import "../libraries/CommonLibrary.sol";

contract VeloAdapter is IAdapter {
    error InvalidParams();
    error PriceManipulationDetected();
    error NotEnoughObservations();

    using SafeERC20 for IERC20;

    struct SecurityParams {
        uint16 anomalyLookback;
        uint16 anomalyOrder;
        uint256 anomalyFactorD9;
    }

    uint256 public constant Q96 = 2**96;
    uint256 public constant D9 = 1e9;

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

        IERC20(pool.token0()).safeApprove(address(positionManager), 0);
        IERC20(pool.token1()).safeApprove(address(positionManager), 0);
    }

    function swapNft(
        address from,
        address vault,
        uint256 newNft
    ) external returns (uint256 oldNft) {
        oldNft = IVeloVault(vault).tokenId();
        IVeloVault(vault).unstakeTokenId();
        positionManager.safeTransferFrom(from, vault, newNft);
        if (oldNft != 0) {
            positionManager.burn(oldNft);
        }
        IVeloVault(vault).stakeTokenId();
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
        if (tokenId_ != 0) {
            (, , , , , tickLower, tickUpper, liquidity, , , , ) = positionManager.positions(tokenId_);
        }
    }

    function tokenId(address vault) external view returns (uint256) {
        return IVeloVault(vault).tokenId();
    }

    function slot0EnsureNoMEV(address poolAddress, bytes memory params)
        external
        view
        returns (uint160 sqrtPriceX96, int24 spotTick)
    {
        if (params.length == 0) return slot0(poolAddress);
        SecurityParams memory securityParams = abi.decode(params, (SecurityParams));
        uint32[] memory timestamps = new uint32[](securityParams.anomalyLookback + 2);
        int56[] memory tickCumulatives = new int56[](timestamps.length);
        uint16 observationIndex;
        uint16 observationCardinality;
        (sqrtPriceX96, spotTick, observationIndex, observationCardinality, , ) = ICLPool(poolAddress).slot0();
        if (observationCardinality < timestamps.length) revert NotEnoughObservations();
        for (uint16 i = 0; i < timestamps.length; i++) {
            uint16 index = (observationCardinality + observationIndex - i) % observationCardinality;
            (timestamps[i], tickCumulatives[i], , ) = ICLPool(poolAddress).observations(index);
        }

        int24[] memory ticks = new int24[](timestamps.length);
        ticks[0] = spotTick;
        for (uint256 i = 0; i + 1 < timestamps.length - 1; i++) {
            ticks[i + 1] = int24(
                (tickCumulatives[i] - tickCumulatives[i + 1]) / int56(uint56(timestamps[i] - timestamps[i + 1]))
            );
        }

        uint256[] memory deltas = new uint256[](securityParams.anomalyLookback + 1);
        for (uint256 i = 0; i < deltas.length; i++) {
            int24 delta = ticks[i] - ticks[i + 1];
            if (delta > 0) delta = -delta;
            deltas[i] = uint256(uint24(delta));
        }

        CommonLibrary.sortUint(deltas);
        if (
            deltas[deltas.length - 1] >
            FullMath.mulDiv(deltas[securityParams.anomalyOrder], securityParams.anomalyFactorD9, D9)
        ) {
            revert PriceManipulationDetected();
        }
    }

    function getOraclePrice(address pool) external view override returns (uint160, int24) {
        (
            uint160 spotSqrtPriceX96,
            int24 spotTick,
            uint16 observationIndex,
            uint16 observationCardinality,
            ,

        ) = ICLPool(pool).slot0();
        if (observationCardinality < 2) revert NotEnoughObservations();
        (uint32 blockTimestamp, int56 tickCumulative, , ) = ICLPool(pool).observations(observationIndex);
        if (block.timestamp != blockTimestamp) return (spotSqrtPriceX96, spotTick);
        uint16 previousObservationIndex = observationCardinality - 1;
        if (observationIndex != 0) previousObservationIndex = observationIndex - 1;
        if (previousObservationIndex == observationCardinality) revert NotEnoughObservations();
        (uint32 previousBlockTimestamp, int56 previousTickCumulative, , ) = ICLPool(pool).observations(
            previousObservationIndex
        );
        int56 tickCumulativesDelta = tickCumulative - previousTickCumulative;
        int24 tick = int24(tickCumulativesDelta / int56(uint56(blockTimestamp - previousBlockTimestamp)));
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        return (sqrtPriceX96, tick);
    }

    function slot0(address poolAddress) public view returns (uint160 sqrtPriceX96, int24 spotTick) {
        (sqrtPriceX96, spotTick, , , , ) = ICLPool(poolAddress).slot0();
    }

    function validateSecurityParams(bytes memory params) external pure {
        SecurityParams memory securityParams = abi.decode(params, (SecurityParams));
        if (securityParams.anomalyLookback <= securityParams.anomalyOrder) revert InvalidParams();
        if (securityParams.anomalyFactorD9 > D9 * 10) revert InvalidParams();
    }
}
