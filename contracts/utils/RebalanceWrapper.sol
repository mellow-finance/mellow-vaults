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

    // -------------------  EXTERNAL, MUTATING  -------------------

    function rebalanceUniV3Vaults(int24 offchainTick) external {
        _requireAtLeastOperator();
        IUniswapV3Pool pool = strategy.lowerVault().pool();
        (, int24 spotTick, , , , , ) = pool.slot0();
        require(
            offchainTick + maxTicksDelta >= spotTick && offchainTick - maxTicksDelta <= spotTick,
            ExceptionsLibrary.INVALID_STATE
        );
        uint256[] memory minValues = new uint256[](2);

        strategy.rebalanceUniV3Vaults(minValues, minValues, block.timestamp + 1);
    }

    function rebalanceERC20UniV3Vaults(int24 offchainTick) external {
        _requireAtLeastOperator();
        IUniswapV3Pool pool = strategy.lowerVault().pool();
        (, int24 spotTick, , , , , ) = pool.slot0();
        require(
            offchainTick + maxTicksDelta >= spotTick && offchainTick - maxTicksDelta <= spotTick,
            ExceptionsLibrary.INVALID_STATE
        );
        uint256[] memory minValues = new uint256[](2);

        strategy.rebalanceERC20UniV3Vaults(minValues, minValues, block.timestamp + 1);
    }
}
