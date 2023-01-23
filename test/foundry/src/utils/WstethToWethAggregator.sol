// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/external/chainlink/IAggregatorV3.sol";
import "../libraries/external/FullMath.sol";
import "../libraries/ExceptionsLibrary.sol";
import "forge-std/console2.sol";

contract AggregatorV3wstEth is IAggregatorV3 {
    address public immutable wsteth;
    IAggregatorV3 public immutable eth_oracle;
    IAggregatorV3 public immutable steth_eth_oracle;
    bytes4 public constant TOKENS_PER_STETH_SELECTOR = 0x9576a0c8;
    uint256 public constant D18 = 10**18;

    constructor(address wsteth_, IAggregatorV3 steth_eth_oracle_, IAggregatorV3 eth_oracle_) {
        wsteth = wsteth_;
        steth_eth_oracle = steth_eth_oracle_;
        eth_oracle = eth_oracle_;
    }

    function decimals() external view returns (uint8) {
        return 8;
    }

    function description() external view returns (string memory) {
        return "WSTETH / USD";
    }

    function version() external view returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _roundId)
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
        revert(ExceptionsLibrary.DISABLED);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        )
    {
        (, int256 answerSteth, , ,) = steth_eth_oracle.latestRoundData();
        (, answer, , , ) = eth_oracle.latestRoundData();
        
        answer = _stethToWsteth(int256(FullMath.mulDiv(uint256(answer), uint256(answerSteth), D18)));
    }

    function _stethToWsteth(int256 amount) internal view returns (int256) {
        (bool res, bytes memory data) = wsteth.staticcall(abi.encodePacked(TOKENS_PER_STETH_SELECTOR));
        if (!res) {
            assembly {
                let returndata_size := mload(data)
                revert(add(32, data), returndata_size)
            }
        }
        uint256 tokensPerStEth = abi.decode(data, (uint256));
        return int256(FullMath.mulDiv(uint256(amount), 10**18, tokensPerStEth));
    }
}
