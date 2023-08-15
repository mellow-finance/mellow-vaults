// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAuraBooster {
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns (bool);

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards; // -> BaseRewardPool where 
        address stash;
        bool shutdown;
    }

    function poolInfo(uint256 pid) external view returns (PoolInfo memory); // returns info abount pool by its id
}
