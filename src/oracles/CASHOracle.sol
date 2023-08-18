// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../interfaces/external/chainlink/IAggregatorV3.sol";

import "../libraries/external/OracleLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";

contract CASHOracle is IAggregatorV3 {
    address public constant USDC_USD_ORACLE = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;
    address public constant CASH_USDC_POOL = 0x619259F699839dD1498FFC22297044462483bD27;
    address public constant CASH = 0x5D066D022EDE10eFa2717eD3D79f22F949F8C175;
    uint32 public constant TIMESPAN = 60; // seconds
    uint256 public constant Q96 = 2**96;

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "CASH / USD";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        pure
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        )
    {
        revert("NotImplementedError");
    }

    function latestAnswer() public view returns (int256 answer) {
        (int24 avgTick, , bool withFail) = OracleLibrary.consult(CASH_USDC_POOL, TIMESPAN);
        if (withFail) revert("UnstablePool");
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(avgTick);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (IUniswapV3Pool(CASH_USDC_POOL).token1() == CASH) {
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        }
        (, int256 usdcToUsd, , , ) = IAggregatorV3(USDC_USD_ORACLE).latestRoundData();
        answer = int256(FullMath.mulDiv(priceX96, uint256(usdcToUsd) * 1e12, Q96));
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = IAggregatorV3(USDC_USD_ORACLE).latestRoundData();
        answer = latestAnswer();
    }
}
