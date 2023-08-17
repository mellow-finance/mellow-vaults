// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "../interfaces/external/chainlink/IAggregatorV3.sol";
import {IVault, IERC20} from "../interfaces/external/balancer/vault/IVault.sol";

import "../libraries/external/FullMath.sol";

/// @notice Contract for getting chainlink data
contract AuraOracle is IAggregatorV3 {
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
    bytes32 public constant AURA_WETH_50_50_POOL_ID =
        0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274;

    address public constant ETH_USD_ORACLE = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function description() external pure returns (string memory) {
        return "AURA / USD";
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
        (IERC20[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock) = IVault(BALANCER_VAULT)
            .getPoolTokens(AURA_WETH_50_50_POOL_ID);

        if (lastChangeBlock == block.number) revert("Unstable state");

        (, int256 ethToUsd, , , ) = IAggregatorV3(ETH_USD_ORACLE).latestRoundData();

        if (AURA == address(tokens[0])) {
            answer = int256(FullMath.mulDiv(uint256(ethToUsd), balances[1], balances[0]));
        } else {
            answer = int256(FullMath.mulDiv(uint256(ethToUsd), balances[0], balances[1]));
        }
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
        answer = latestAnswer();
    }
}
