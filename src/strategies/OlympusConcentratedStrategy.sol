// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../libraries/CommonLibrary.sol";
import "../utils/DefaultAccessControl.sol";

import {BasePulseStrategy, IUniV3Vault, TickMath} from "./BasePulseStrategy.sol";

import "../interfaces/external/olympus/IOlympusRange.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";

contract OlympusConcentratedStrategy is DefaultAccessControl {
    uint256 public constant Q96 = 2**96;

    struct MutableParams {
        int24 intervalWidth;
        int24 tickNeighborhood;
    }

    BasePulseStrategy public immutable baseStrategy;
    IOlympusRange public immutable range;
    int24 public immutable tickSpacing;
    uint8 public immutable ohmDecimals;
    uint8 public immutable reserveDecimals;
    uint8 public immutable priceDecimals;
    bool public immutable isFirstOhm;

    MutableParams public mutableParams;

    constructor(
        address admin_,
        BasePulseStrategy baseStrategy_,
        IOlympusRange range_,
        int24 tickSpacing_,
        uint8 ohmDecimals_,
        uint8 reserveDecimals_,
        uint8 priceDecimals_,
        bool isFirstOhm_
    ) DefaultAccessControl(admin_) {
        baseStrategy = baseStrategy_;
        range = range_;
        tickSpacing = tickSpacing_;
        ohmDecimals = ohmDecimals_;
        reserveDecimals = reserveDecimals_;
        priceDecimals = priceDecimals_;
        isFirstOhm = isFirstOhm_;
    }

    function updateMutableParams(MutableParams memory newMutableParams) external {
        _requireAdmin();
        mutableParams = newMutableParams;
    }

    function calculatePulseInterval() public view returns (BasePulseStrategy.Interval memory interval) {
        MutableParams memory mutableParams_ = mutableParams;
        (, IUniV3Vault vault, ) = baseStrategy.immutableParams();
        (, int24 spotTick, , , , , ) = vault.pool().slot0();
        uint256 uniV3Nft = vault.uniV3Nft();

        if (uniV3Nft != 0) {
            (, , , , , interval.lowerTick, interval.upperTick, , , , , ) = baseStrategy.positionManager().positions(
                uniV3Nft
            );
            if (
                mutableParams_.tickNeighborhood + interval.lowerTick <= spotTick &&
                spotTick <= interval.upperTick - mutableParams_.tickNeighborhood &&
                mutableParams_.intervalWidth == interval.upperTick - interval.lowerTick
            ) {
                return interval;
            }
        }

        int24 reminder = spotTick % tickSpacing;
        if (reminder < 0) reminder += tickSpacing;
        int24 centralTick = spotTick - reminder;
        if (reminder * 2 > tickSpacing) {
            centralTick += tickSpacing;
        }

        interval.lowerTick = centralTick - mutableParams_.intervalWidth / 2;
        interval.upperTick = centralTick + mutableParams_.intervalWidth / 2;
    }

    function calculateOlympusInterval() public view returns (BasePulseStrategy.Interval memory) {
        uint256 lowerCushionPrice = range.price(false, false);
        uint256 upperCushionPrice = range.price(false, true);

        uint256 lowerPriceX96;
        uint256 upperPriceX96;

        if (isFirstOhm) {
            lowerPriceX96 = FullMath.mulDiv(
                Q96,
                10**reserveDecimals * lowerCushionPrice,
                10**ohmDecimals * 10**priceDecimals
            );
            upperPriceX96 = FullMath.mulDiv(
                Q96,
                10**reserveDecimals * upperCushionPrice,
                10**ohmDecimals * 10**priceDecimals
            );
        } else {
            lowerPriceX96 = FullMath.mulDiv(
                Q96,
                10**ohmDecimals * 10**priceDecimals,
                10**reserveDecimals * upperCushionPrice
            );
            upperPriceX96 = FullMath.mulDiv(
                Q96,
                10**ohmDecimals * 10**priceDecimals,
                10**reserveDecimals * lowerCushionPrice
            );
        }

        uint160 lowerSqrtPriceX96 = uint160(CommonLibrary.sqrtX96(lowerPriceX96));
        uint160 upperSqrtPriceX96 = uint160(CommonLibrary.sqrtX96(upperPriceX96));

        int24 lowerTick = TickMath.getTickAtSqrtRatio(lowerSqrtPriceX96);
        int24 upperTick = TickMath.getTickAtSqrtRatio(upperSqrtPriceX96);

        {
            int24 reminder = lowerTick % tickSpacing;
            if (reminder < 0) reminder += tickSpacing;
            if (reminder != 0) {
                lowerTick -= reminder;
            }
        }

        {
            int24 reminder = upperTick % tickSpacing;
            if (reminder < 0) reminder += tickSpacing;
            if (reminder != 0) {
                upperTick += tickSpacing - reminder;
            }
        }

        return BasePulseStrategy.Interval({lowerTick: lowerTick, upperTick: upperTick});
    }

    function calculateInterval() public view returns (BasePulseStrategy.Interval memory) {
        BasePulseStrategy.Interval memory pulseInterval = calculatePulseInterval();
        BasePulseStrategy.Interval memory olympusInterval = calculateOlympusInterval();
        if (pulseInterval.lowerTick > olympusInterval.lowerTick) olympusInterval.lowerTick = pulseInterval.lowerTick;
        if (pulseInterval.upperTick < olympusInterval.upperTick) olympusInterval.upperTick = pulseInterval.upperTick;
        if (olympusInterval.lowerTick + tickSpacing > olympusInterval.upperTick) {
            return pulseInterval;
        }
        return olympusInterval;
    }

    function rebalance(
        uint256 deadline,
        bytes memory swapData,
        uint256 minAmountInCaseOfSwap
    ) external {
        _requireAtLeastOperator();

        baseStrategy.rebalance(deadline, calculateInterval(), swapData, minAmountInCaseOfSwap);
    }
}
