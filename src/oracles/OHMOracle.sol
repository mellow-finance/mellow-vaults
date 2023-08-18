// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/external/chainlink/IAggregatorV3.sol";

import "../libraries/external/FullMath.sol";

/// @notice Contract for getting chainlink data
contract OHMOracle is IAggregatorV3 {
    address public constant OHM_ETH_ORACLE = 0x9a72298ae3886221820B1c878d12D872087D3a23;
    address public constant ETH_USD_ORACLE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "OHM / USD";
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

    function latestAnswer() external view returns (int256 answer) {
        (, answer, , , ) = IAggregatorV3(ETH_USD_ORACLE).latestRoundData();
        (, int256 ohmEthAnswer, , , ) = IAggregatorV3(OHM_ETH_ORACLE).latestRoundData();
        answer = int256(FullMath.mulDiv(uint256(ohmEthAnswer), uint256(answer), 10**18));
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
        (roundId, answer, startedAt, updatedAt, answeredInRound) = IAggregatorV3(ETH_USD_ORACLE).latestRoundData();
        (, int256 ohmEthAnswer, , , ) = IAggregatorV3(OHM_ETH_ORACLE).latestRoundData();
        answer = int256(FullMath.mulDiv(uint256(ohmEthAnswer), uint256(answer), 10**18));
    }
}
