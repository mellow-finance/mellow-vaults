// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAuraBaseRewardPool {
    function balanceOf(address account) external view returns (uint256);

    function userRewardPerTokenPaid(address account) external view returns (uint256);

    function rewards(address account) external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function getReward() external returns (bool);

    function pid() external view returns (uint256);

    function withdrawAllAndUnwrap(bool claim) external;
}
