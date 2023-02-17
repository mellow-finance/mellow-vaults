// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

// https://docs.synthetix.io/contracts/source/interfaces/istakingrewards
interface IFarmingPool {
    // Views

    function balanceOf(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    // Mutative

    function getReward() external;

    function stake(address to, uint256 amount) external;

    function withdraw(address to, uint256 amount) external;

    function setRewardsDuration(uint256 duration) external;

    function notifyRewardAmount(uint256 amount) external;
}