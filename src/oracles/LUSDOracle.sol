// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../interfaces/external/chainlink/IAggregatorV3.sol";

import "../libraries/external/OracleLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/external/TickMath.sol";

contract LUSDOracle is IAggregatorV3 {
    address public constant USDC_USD_ORACLE = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public constant LUSD_USDC_POOL = 0x4e0924d3a751bE199C426d52fb1f2337fa96f736;
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    uint32 public constant TIMESPAN = 60; // seconds
    uint256 public constant Q96 = 2**96;

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "LUSD / USD";
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
        (int24 avgTick, , bool withFail) = OracleLibrary.consult(LUSD_USDC_POOL, TIMESPAN);
        if (withFail) revert("UnstablePool");
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(avgTick);
        uint256 priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);
        if (IUniswapV3Pool(LUSD_USDC_POOL).token1() == LUSD) {
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
