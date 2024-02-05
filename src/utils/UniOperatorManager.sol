// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/INonfungiblePositionManager.sol";

import "../libraries/CommonLibrary.sol";

import "../strategies/PulseOperatorStrategy.sol";

import "./DefaultAccessControl.sol";

contract UniOperatorManager is DefaultAccessControl {
    uint16 public constant MAX_OBSERVATIONS = 1000;
    uint16 public constant DEFAULT_OBSERVATION_CARDINALITY = 600;
    int24 public constant POSITION_WIDTH_COEFFICIENT = 4; // positionWidth = sigma * coeffient
    int24 public constant MAX_POSITION_WIDTH_COEFFICIENT = 2; // maxPositionWidth = positionWidth * coefficient

    constructor(address admin) DefaultAccessControl(admin) {}

    function manage(PulseOperatorStrategy[] memory strategies)
        external
        returns (int24[] memory positionWidths, int24[] memory maxPositionWidths)
    {
        _requireAtLeastOperator();
        positionWidths = new int24[](strategies.length);
        maxPositionWidths = new int24[](strategies.length);
        for (uint256 i = 0; i < strategies.length; i++) {
            (positionWidths[i], maxPositionWidths[i]) = _manage(strategies[i]);
        }
    }

    function _manage(PulseOperatorStrategy strategy) private returns (int24 positionWidth, int24 maxPositionWidth) {
        PulseOperatorStrategy.ImmutableParams memory params = strategy.getImmutableParams();
        IUniswapV3Pool pool = IUniswapV3Pool(params.strategy.getImmutableParams().pool);
        (positionWidth, maxPositionWidth) = get(pool, params.tickSpacing);
        if (positionWidth != 0 && maxPositionWidth != 0) {
            PulseOperatorStrategy.MutableParams memory mutableParams = strategy.getMutableParams();
            mutableParams.positionWidth = positionWidth;
            mutableParams.maxPositionWidth = maxPositionWidth;
            strategy.updateMutableParams(mutableParams);
        }
    }

    struct Stack {
        int24 nextTick;
        uint16 observationIndex;
        uint16 observationCardinality;
        uint32 nextTimestamp;
        int56 nextCumulativeTick;
    }

    function get(IUniswapV3Pool pool, int24 tickSpacing) public returns (int24 positionWidth, int24 maxPositionWidth) {
        Stack memory stack;

        {
            uint16 observationCardinalityNext;
            (
                ,
                stack.nextTick,
                stack.observationIndex,
                stack.observationCardinality,
                observationCardinalityNext,
                ,

            ) = IUniswapV3Pool(pool).slot0();
            if (observationCardinalityNext < DEFAULT_OBSERVATION_CARDINALITY) {
                pool.increaseObservationCardinalityNext(DEFAULT_OBSERVATION_CARDINALITY);
            }
        }
        if (stack.observationCardinality * 2 < DEFAULT_OBSERVATION_CARDINALITY) {
            // waiting for more observations
            return (0, 0);
        }

        (uint32 nextTimestamp, int56 nextCumulativeTick, , ) = pool.observations(stack.observationIndex);
        uint16 lookback = stack.observationCardinality - 1;
        if (lookback > MAX_OBSERVATIONS) {
            lookback = MAX_OBSERVATIONS;
        }
        int24 sigma;
        {
            int48 averageSqrDelta = 0;
            int48 averageDelta = 0;
            for (uint16 i = 1; i <= lookback; i++) {
                uint256 index = (stack.observationCardinality + stack.observationIndex - i) %
                    stack.observationCardinality;
                (uint32 timestamp, int56 tickCumulative, , ) = pool.observations(index);
                int24 tick = int24((nextCumulativeTick - tickCumulative) / int56(uint56(nextTimestamp - timestamp)));

                int48 delta = stack.nextTick - tick;
                if (delta < 0) delta = -delta;
                averageDelta += delta;
                averageSqrDelta += delta**2;

                (nextTimestamp, nextCumulativeTick) = (timestamp, tickCumulative);
                stack.nextTick = tick;
            }
            averageDelta /= int16(lookback);
            averageSqrDelta /= int16(lookback);

            int48 d = averageSqrDelta - averageDelta**2;
            sigma = int24(int256(CommonLibrary.sqrt(uint48(d))));
        }
        {
            uint256 timespan = block.timestamp - nextTimestamp;
            int24 coefficient = int24(int256(CommonLibrary.sqrt((7 days * 1000) / timespan)));
            positionWidth = sigma * coefficient * POSITION_WIDTH_COEFFICIENT;
        }
        if (positionWidth % tickSpacing != 0 || positionWidth == 0) {
            positionWidth += tickSpacing - (positionWidth % tickSpacing);
        }
        maxPositionWidth = positionWidth * MAX_POSITION_WIDTH_COEFFICIENT;
    }
}
