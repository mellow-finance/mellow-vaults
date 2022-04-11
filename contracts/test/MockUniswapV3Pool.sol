// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.9;

import "../interfaces/external/univ3/IUniswapV3Pool.sol";

contract MockUniswapV3Pool is IUniswapV3Pool {
    struct Slot0Params {
        uint160 sqrtPriceX96;
        int24 tick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint16 observationCardinalityNext;
        uint8 feeProtocol;
        bool unlocked;
    }

    struct ObservationsParams {
        uint32 blockTimestamp;
        int56 tickCumulative;
        uint160 secondsPerLiquidityCumulativeX128;
        bool initialized;
        uint32 blockTimestampLast;
        int56 tickCumulativeLast;
        uint8 observationsCalled;
    }

    Slot0Params private slotParams;
    ObservationsParams private observationsParams;

    function initialize(uint160 sqrtPriceX96) external {}

    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1) {}

    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1) {}

    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1) {}

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {}

    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {}

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external {}

    function factory() external view returns (address) {}

    function token0() external view returns (address) {}

    function token1() external view returns (address) {}

    function fee() external view returns (uint24) {}

    function tickSpacing() external view returns (int24) {}

    function maxLiquidityPerTick() external view returns (uint128) {}

    function setSlot0Params(
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    ) external {
        slotParams.sqrtPriceX96 = sqrtPriceX96;
        slotParams.tick = tick;
        slotParams.observationIndex = observationIndex;
        slotParams.observationCardinality = observationCardinality;
        slotParams.observationCardinalityNext = observationCardinalityNext;
        slotParams.feeProtocol = feeProtocol;
        slotParams.unlocked = unlocked;
    }

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        sqrtPriceX96 = slotParams.sqrtPriceX96;
        tick = slotParams.tick;
        observationIndex = slotParams.observationIndex;
        observationCardinality = slotParams.observationCardinality;
        observationCardinalityNext = slotParams.observationCardinalityNext;
        feeProtocol = slotParams.feeProtocol;
        unlocked = slotParams.unlocked;
    }

    function feeGrowthGlobal0X128() external view returns (uint256) {}

    function feeGrowthGlobal1X128() external view returns (uint256) {}

    function protocolPerformanceFees() external view returns (uint128 token0, uint128 token1) {}

    function liquidity() external view returns (uint128) {}

    function ticks(int24 tick)
        external
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        )
    {}

    function tickBitmap(int16 wordPosition) external view returns (uint256) {}

    function positions(bytes32 key)
        external
        view
        returns (
            uint128 _liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {}

    function setObservationsParams(
        uint32 blockTimestamp,
        int56 tickCumulative,
        uint160 secondsPerLiquidityCumulativeX128,
        bool initialized,
        uint32 blockTimestampLast,
        int56 tickCumulativeLast
    ) external {
        observationsParams.blockTimestamp = blockTimestamp;
        observationsParams.tickCumulative = tickCumulative;
        observationsParams.secondsPerLiquidityCumulativeX128 = secondsPerLiquidityCumulativeX128;
        observationsParams.initialized = initialized;
        observationsParams.blockTimestampLast = blockTimestampLast;
        observationsParams.tickCumulativeLast = tickCumulativeLast;
        observationsParams.observationsCalled = 0;
    }

    function observations(uint256 index)
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        )
    {
        if (index == slotParams.observationIndex) {
            blockTimestamp = observationsParams.blockTimestamp;
            tickCumulative = observationsParams.tickCumulative;
        } else {
            blockTimestamp = observationsParams.blockTimestampLast;
            tickCumulative = observationsParams.tickCumulativeLast;
        }
        secondsPerLiquidityCumulativeX128 = observationsParams.secondsPerLiquidityCumulativeX128;
        initialized = observationsParams.initialized;
    }
}
