// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/external/velo/ICLPool.sol";
import "../interfaces/external/velo/INonfungiblePositionManager.sol";

import "../libraries/CommonLibrary.sol";

import "../strategies/BaseAmmStrategy.sol";
import "../strategies/PulseOperatorStrategy.sol";

import "./DefaultAccessControl.sol";

contract VeloOperatorManager is DefaultAccessControl {
    using SafeERC20 for IERC20;

    uint16 public constant MAX_OBSERVATIONS = 60000;
    uint16 public constant DEFAULT_OBSERVATION_CARDINALITY = 600;
    int24 public constant POSITION_WIDTH_COEFFICIENT = 3; // positionWidth = sigma * coeffient
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
        PulseOperatorStrategy.ImmutableParams memory operatorImmutableParams = strategy.getImmutableParams();
        ICLPool pool = ICLPool(operatorImmutableParams.strategy.getImmutableParams().pool);
        (
            ,
            int24 spotTick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,

        ) = ICLPool(pool).slot0();
        if (observationCardinalityNext < DEFAULT_OBSERVATION_CARDINALITY) {
            pool.increaseObservationCardinalityNext(DEFAULT_OBSERVATION_CARDINALITY);
            return (0, 0);
        }
        if (observationCardinality * 2 < DEFAULT_OBSERVATION_CARDINALITY) {
            // waiting for more observations
            return (0, 0);
        }

        (uint32 nextTimestamp, int56 nextCumulativeTick, , ) = pool.observations(observationIndex);
        int24 nextTick = spotTick;
        uint16 lookback = observationCardinality;
        if (lookback > MAX_OBSERVATIONS) {
            lookback = MAX_OBSERVATIONS;
        }
        int24 sigma;
        {
            int24[] memory deltas = new int24[](lookback);

            int24 averageDelta = 0;
            for (uint16 i = 1; i <= lookback; i++) {
                uint256 index = (observationCardinality + observationIndex - i) % observationCardinality;
                (uint32 timestamp, int56 tickCumulative, , ) = pool.observations(index);
                int24 tick = int24((nextCumulativeTick - tickCumulative) / int56(uint56(nextTimestamp - timestamp)));

                int24 delta = nextTick - tick;
                if (delta < 0) delta = -delta;
                averageDelta += delta;
                deltas[i - 1] = delta;

                (nextTimestamp, nextCumulativeTick) = (timestamp, tickCumulative);
                nextTick = tick;
            }
            averageDelta /= int16(observationCardinality);

            {
                int48 d = 0;
                for (uint16 i = 0; i < lookback; i++) {
                    d += (deltas[i] - averageDelta)**2;
                }
                d /= int16(lookback - 1);
                sigma = int24(int256(CommonLibrary.sqrt(uint48(d))));
            }
        }

        positionWidth = sigma * POSITION_WIDTH_COEFFICIENT;
        int24 tickSpacing = operatorImmutableParams.tickSpacing;
        if (positionWidth % tickSpacing != 0) {
            positionWidth += tickSpacing - (positionWidth % tickSpacing);
        }
        maxPositionWidth = positionWidth * MAX_POSITION_WIDTH_COEFFICIENT;
        PulseOperatorStrategy.MutableParams memory mutableParams = strategy.getMutableParams();
        mutableParams.positionWidth = positionWidth;
        mutableParams.maxPositionWidth = maxPositionWidth;
        strategy.updateMutableParams(mutableParams);
    }
}
