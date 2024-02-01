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
        uint16 lookback;
        int24 maxAllowedDelta;
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
        uint16 observationIndex;
        uint16 observationCardinality;
        (sqrtPriceX96, spotTick, observationIndex, observationCardinality, , ) = ICLPool(poolAddress).slot0();
        SecurityParams memory securityParams = abi.decode(params, (SecurityParams));
        uint16 lookback = securityParams.lookback;
        if (observationCardinality < lookback + 1) revert NotEnoughObservations();

        (uint32 previousTimestamp, int56 previousCumulativeTick, , ) = ICLPool(poolAddress).observations(
            (observationCardinality + observationIndex - lookback) % observationCardinality
        );

        int24 previousTick;
        for (uint16 i = 0; i <= lookback; i++) {
            int24 tick;
            if (i < lookback) {
                uint256 index = (observationCardinality + observationIndex + 1 + i - lookback) % observationCardinality;
                (uint32 timestamp, int56 tickCumulative, , ) = ICLPool(poolAddress).observations(index);
                tick = int24((tickCumulative - previousCumulativeTick) / int56(uint56(timestamp - previousTimestamp)));
                (previousTimestamp, previousCumulativeTick) = (timestamp, tickCumulative);
            } else {
                tick = spotTick;
            }
            if (i > 0) {
                int24 delta = tick - previousTick;
                if (delta < 0) delta = -delta;
                if (delta > securityParams.maxAllowedDelta) {
                    revert PriceManipulationDetected();
                }
            }
            previousTick = tick;
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
        if (params.length == 0) return;
        SecurityParams memory securityParams = abi.decode(params, (SecurityParams));
        if (securityParams.lookback == 0 || securityParams.maxAllowedDelta < 0) revert InvalidParams();
    }
}
