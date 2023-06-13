// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IPancakeV3Pool.sol";
import "./IMasterChef.sol";

interface ILMPool {
    struct Info {
        // the total position liquidity that references this tick
        uint128 liquidityGross;
        // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
        int128 liquidityNet;
        // reward growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
        // only has relative meaning, not absolute — the value depends on when the tick is initialized
        uint256 rewardGrowthOutsideX128;
    }

    function updatePosition(
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta
    ) external;

    function getRewardGrowthInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (uint256 rewardGrowthInsideX128);

    function accumulateReward(uint32 currTimestamp) external;

    function crossLmTick(int24 tick, bool zeroForOne) external;

    function pool() external view returns (IPancakeV3Pool);

    function masterChef() external view returns (IMasterChef);

    function rewardGrowthGlobalX128() external view returns (uint256);

    function lmTicks(int24) external view returns (Info memory);

    function lmLiquidity() external view returns (uint128);

    function lastRewardTimestamp() external view returns (uint32);
}
