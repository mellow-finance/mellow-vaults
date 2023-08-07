// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IPancakeV3Pool.sol";
import "./ILMPool.sol";
import "./IMasterChef.sol";

interface IPancakeV3LMPool {
    function REWARD_PRECISION() external view returns (uint256);

    function pool() external view returns (IPancakeV3Pool);

    function masterChef() external view returns (IMasterChef);

    function firstLMPool() external view returns (ILMPool);

    function secondLMPool() external view returns (ILMPool);

    function thirdLMPool() external view returns (ILMPool);

    function lmTicksFlag(int24) external view returns (bool);

    function rewardGrowthGlobalX128() external view returns (uint256);

    function oldLMPool() external view returns (IPancakeV3LMPool);

    function checkOldLMPool(int24, int24) external view returns (bool);

    function lmTicks(int24) external view returns (ILMPool.Info memory);

    function lmLiquidity() external view returns (uint128);

    function lastRewardTimestamp() external view returns (uint32);

    function negativeRewardGrowthInsideInitValue(int24, int24) external view returns (uint256);

    function checkThirdLMPool(int24, int24) external view returns (bool);

    function getRewardGrowthInside(
        int24 tickLower,
        int24 tickUpper
    ) external view returns (uint256 rewardGrowthInsideX128);
}
