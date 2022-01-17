// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/oracles/IChainlinkOracle.sol";
import "../interfaces/oracles/IUniV3Oracle.sol";
import "../interfaces/oracles/IUniV2Oracle.sol";
import "../interfaces/oracles/IMellowOracle.sol";
import "../libraries/CommonLibrary.sol";

contract MellowOracle is IMellowOracle {
    IUniV2Oracle public immutable univ2Oracle;
    IUniV3Oracle public immutable univ3Oracle;
    IChainlinkOracle public immutable chainlinkOracle;

    constructor(
        IUniV2Oracle univ2Oracle_,
        IUniV3Oracle univ3Oracle_,
        IChainlinkOracle chainlinkOracle_
    ) {
        univ2Oracle = univ2Oracle_;
        univ3Oracle = univ3Oracle_;
        chainlinkOracle = chainlinkOracle_;
    }

    // -------------------------  EXTERNAL, VIEW  ------------------------------

    /// @inheritdoc IMellowOracle
    function spotPrice(address token0, address token1)
        external
        view
        returns (
            uint256 priceX96,
            uint256 minPriceX96,
            uint256 maxPriceX96
        )
    {
        uint256 len;
        if (address(univ3Oracle) != address(0)) {
            len += 2;
        }
        if (address(univ2Oracle) != address(0)) {
            len += 1;
        }
        if (address(chainlinkOracle) != address(0)) {
            len += 1;
        }
        uint256[] memory values = new uint256[](len);
        len = 0;
        if (address(univ3Oracle) != address(0)) {
            (uint256 spotPriceX96, uint256 avgPriceX96) = univ3Oracle.prices(token0, token1);
            values[0] = spotPriceX96;
            values[1] = avgPriceX96;
            len += 2;
        }
        if (address(univ2Oracle) != address(0)) {
            values[len] = univ2Oracle.spotPrice(token0, token1);
            len += 1;
        }
        if (address(chainlinkOracle) != address(0)) {
            values[len] = chainlinkOracle.spotPrice(token0, token1);
        }
        CommonLibrary.bubbleSortUint(values);
        priceX96 = 0;
        for (uint256 i = 0; i < values.length; i++) {
            priceX96 += values[i];
        }
        priceX96 /= values.length;
        minPriceX96 = values[0];
        maxPriceX96 = values[values.length - 1];
    }
}
