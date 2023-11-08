// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IRewardsDistributor.sol";

interface IMinter {
    function update_period() external returns (uint256);

    function active_period() external view returns (uint256);

    function _rewards_distributor() external view returns (IRewardsDistributor);
}
