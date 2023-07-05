// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../libraries/CommonLibrary.sol";
import "../utils/DefaultAccessControl.sol";

import {BasePulseStrategy, IERC20, IUniV3Vault, TickMath} from "./BasePulseStrategy.sol";

import "../interfaces/external/olympus/IOlympusRange.sol";
import "../interfaces/external/olympus/IOlympusPrice.sol";

contract OlympusStrategy is DefaultAccessControl {
    uint256 public constant Q96 = 2**96;

    BasePulseStrategy public immutable baseStrategy;
    IOlympusRange public immutable range;
    IOlympusPrice public immutable price;
    int24 public immutable tickSpacing;
    address[] private tokens_;

    uint8 public immutable ohmDecimals;
    uint8 public immutable reserveDecimals;
    uint8 public immutable priceDecimals;
    bool public immutable isFirstOhm;

    constructor(
        address admin_,
        BasePulseStrategy baseStrategy_,
        IOlympusRange range_,
        IOlympusPrice price_
    ) DefaultAccessControl(admin_) {
        baseStrategy = baseStrategy_;
        range = range_;

        (, IUniV3Vault uniV3Vault, ) = baseStrategy.immutableParams();
        tickSpacing = uniV3Vault.pool().tickSpacing();
        tokens_ = uniV3Vault.vaultTokens();

        if (tokens_[0] == address(range_.ohm())) {
            isFirstOhm = true;
            ohmDecimals = IERC20(tokens_[0]).decimals();
            reserveDecimals = IERC20(tokens_[1]).decimals();
        } else {
            ohmDecimals = IERC20(tokens_[1]).decimals();
            reserveDecimals = IERC20(tokens_[0]).decimals();
        }

        priceDecimals = price_.decimals();
    }

    function calculateInterval() public view returns (BasePulseStrategy.Interval memory) {
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

        uint160 lowerSqrtPriceX96 = CommonLibrary.sqrtX96(lowerPriceX96);
        uint160 upperSqrtPriceX96 = CommonLibrary.sqrtX96(upperPriceX96);

        int24 lowerTick = TickMath.getTickAtSqrtRatio(lowerSqrtPriceX96);
        int24 upperTick = TickMath.getTickAtSqrtRatio(upperSqrtPriceX96);

        if (lowerTick % tickSpacing != 0) {
            lowerTick -= lowerTick % tickSpacing;
        }

        if (upperTick % tickSpacing != 0) {
            upperTick += tickSpacing - (upperTick % tickSpacing);
        }

        return BasePulseStrategy.Interval({lowerTick: lowerTick, upperTick: upperTick});
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
