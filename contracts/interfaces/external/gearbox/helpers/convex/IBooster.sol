// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IBooster {
    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) external returns (bool);

    function depositAll(uint256 _pid, bool _stake) external returns (bool);

    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    function withdrawAll(uint256 _pid) external returns (bool);

    // function earmarkRewards(uint256 _pid) external returns (bool);

    // function earmarkFees() external returns (bool);

    //
    // GETTERS
    //

    function poolInfo(uint256 i) external view returns (PoolInfo memory);

    function poolLength() external view returns (uint256);

    function staker() external view returns (address);

    function minter() external view returns (address);

    function crv() external view returns (address);

    function registry() external view returns (address);

    function stakerRewards() external view returns (address);

    function lockRewards() external view returns (address);

    function lockFees() external view returns (address);
}