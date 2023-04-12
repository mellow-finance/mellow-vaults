// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../libraries/ExceptionsLibrary.sol";
import "../strategies/LStrategy.sol";
import "./DefaultAccessControl.sol";

contract RebalanceWrapper is DefaultAccessControl {
    LStrategy public strategy;
    int24 public maxTicksDelta;

    constructor(
        address admin,
        address strategy_,
        int24 initialDelta
    ) DefaultAccessControl(admin) {
        strategy = LStrategy(strategy_);
        maxTicksDelta = initialDelta;
    }

    function setDelta(int24 newMaxTicksDelta) external {
        _requireAdmin();
        maxTicksDelta = newMaxTicksDelta;
    }

    function rebalanceUniV3Vaults(int24 offchainTick)
        external
        returns (
            uint256[] memory pulledAmounts,
            uint256[] memory pushedAmounts,
            uint128 depositLiquidity,
            uint128 withdrawLiquidity,
            bool lowerToUpper
        )
    {
        _requireAtLeastOperator();
        _checkPoolState(offchainTick);
        uint256[] memory minValues = new uint256[](2);

        (pulledAmounts, pushedAmounts, depositLiquidity, withdrawLiquidity, lowerToUpper) = strategy
            .rebalanceUniV3Vaults(minValues, minValues, block.timestamp + 1);
    }

    function rebalanceERC20UniV3Vaults(int24 offchainTick)
        external
        returns (
            uint256[] memory totalPulledAmounts,
            bool isNegativeCapitalDelta,
            uint256 percentageIncreaseD
        )
    {
        _requireAtLeastOperator();
        _checkPoolState(offchainTick);
        uint256[] memory minValues = new uint256[](2);

        (totalPulledAmounts, isNegativeCapitalDelta, percentageIncreaseD) = strategy.rebalanceERC20UniV3Vaults(
            minValues,
            minValues,
            block.timestamp + 1
        );
    }

    function _checkPoolState(int24 offchainTick) internal view {
        IUniswapV3Pool pool = strategy.lowerVault().pool();
        (, int24 spotTick, , , , , ) = pool.slot0();
        require(
            offchainTick + maxTicksDelta >= spotTick && offchainTick - maxTicksDelta <= spotTick,
            ExceptionsLibrary.INVALID_STATE
        );
    }
}
