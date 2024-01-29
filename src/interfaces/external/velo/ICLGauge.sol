// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {IVoter} from "./IVoter.sol";
import {ICLPool} from "./ICLPool.sol";

interface ICLGauge {
    event NotifyReward(address indexed from, uint256 amount);
    event Deposit(address indexed user, uint256 indexed tokenId, uint128 indexed liquidityToStake);
    event Withdraw(address indexed user, uint256 indexed tokenId, uint128 indexed liquidityToStake);
    event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);
    event ClaimRewards(address indexed from, uint256 amount);

    /// @notice NonfungiblePositionManager used to create nfts this gauge accepts
    function nft() external view returns (INonfungiblePositionManager);

    /// @notice Voter contract gauge receives emissions from
    function voter() external view returns (IVoter);

    /// @notice Address of the CL pool linked to the gauge
    function pool() external view returns (ICLPool);

    /// @notice Address of the forwarder
    function forwarder() external view returns (address);

    /// @notice Address of the FeesVotingReward contract linked to the gauge
    function feesVotingReward() external view returns (address);

    /// @notice Timestamp end of current rewards period
    function periodFinish() external view returns (uint256);

    /// @notice Current reward rate of rewardToken to distribute per second
    function rewardRate() external view returns (uint256);

    /// @notice Claimable rewards by tokenId
    function rewards(uint256 tokenId) external view returns (uint256);

    /// @notice Most recent timestamp tokenId called updateRewards
    function lastUpdateTime(uint256 tokenId) external view returns (uint256);

    /// @notice View to see the rewardRate given the timestamp of the start of the epoch
    function rewardRateByEpoch(uint256) external view returns (uint256);

    /// @notice Cached address of token0, corresponding to token0 of the pool
    function token0() external view returns (address);

    /// @notice Cached address of token1, corresponding to token1 of the pool
    function token1() external view returns (address);

    /// @notice Cached amount of fees generated from the Pool linked to the Gauge of token0
    function fees0() external view returns (uint256);

    /// @notice Cached amount of fees generated from the Pool linked to the Gauge of token1
    function fees1() external view returns (uint256);

    /// @notice Total amount of rewardToken to distribute for the current rewards period
    function left() external view returns (uint256 _left);

    /// @notice Address of the emissions token
    function rewardToken() external view returns (address);

    /// @notice To provide compatibility support with the old voter
    function isPool() external view returns (bool);

    /// @notice Returns the rewardGrowthInside of the position at the last user action (deposit, withdraw, getReward)
    /// @param tokenId The tokenId of the position
    /// @return The rewardGrowthInside for the position
    function rewardGrowthInside(uint256 tokenId) external view returns (uint256);

    /// @notice Called on gauge creation by CLGaugeFactory
    /// @param _forwarder The address of the forwarder contract
    /// @param _pool The address of the pool
    /// @param _feesVotingReward The address of the feesVotingReward contract
    /// @param _rewardToken The address of the reward token
    /// @param _voter The address of the voter contract
    /// @param _nft The address of the nft position manager contract
    /// @param _token0 The address of token0 of the pool
    /// @param _token1 The address of token1 of the pool
    /// @param _isPool Whether the attached pool is a real pool or not
    function initialize(
        address _forwarder,
        address _pool,
        address _feesVotingReward,
        address _rewardToken,
        address _voter,
        address _nft,
        address _token0,
        address _token1,
        bool _isPool
    ) external;

    /// @notice Returns the claimable rewards for a given account and tokenId
    /// @dev Throws if account is not the position owner
    /// @dev pool.updateRewardsGrowthGlobal() needs to be called first, to return the correct claimable rewards
    /// @param account The address of the user
    /// @param tokenId The tokenId of the position
    /// @return The amount of claimable reward
    function earned(address account, uint256 tokenId) external view returns (uint256);

    /// @notice Retrieve rewards for a tokenId
    /// @dev Throws if not called by the position owner
    /// @param tokenId The tokenId of the position
    function getReward(uint256 tokenId) external;

    /// @notice Notifies gauge of gauge rewards.
    /// @param amount Amount of gauge rewards (emissions) to notify. Must be greater than 604_800.
    function notifyRewardAmount(uint256 amount) external;

    /// @dev Notifies gauge of gauge rewards without distributing its fees.
    ///      Assumes gauge reward tokens is 18 decimals.
    ///      If not 18 decimals, rewardRate may have rounding issues.
    /// @param amount Amount of gauge rewards (emissions) to notify. Must be greater than 604_800.
    function notifyRewardWithoutClaim(uint256 amount) external;

    /// @notice Used to deposit a CL position into the gauge
    /// @notice Allows the user to receive emissions instead of fees
    /// @param tokenId The tokenId of the position
    function deposit(uint256 tokenId) external;

    /// @notice Used to withdraw a CL position from the gauge
    /// @notice Allows the user to receive fees instead of emissions
    /// @notice Outstanding emissions will be collected on withdrawal
    /// @param tokenId The tokenId of the position
    function withdraw(uint256 tokenId) external;

    /// @notice Used to increase liquidity of a staked position
    /// @param tokenId The tokenId of the position
    /// @param amount0Desired The desired amount of token0 to be staked,
    /// @param amount1Desired The desired amount of token1 to be staked,
    /// @param amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// @param amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// @param deadline The time by which the transaction must be included to effect the change
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return amount0 The amount of token0 required to obtain new liquidity amount
    /// @return amount1 The amount of token1 required to obtain new liquidity amount
    function increaseStakedLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 deadline
    )
        external
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    /// @notice Used to decrease liquidity of a staked position
    /// @param tokenId The tokenId of the position
    /// @param liquidity The amount of liquidity to be unstaked from the gauge
    /// @param amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// @param amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// @param deadline The time by which the transaction must be included to effect the change
    /// @return amount0 The amount of token0 decreased from position
    /// @return amount1 The amount of token1 decreased from position
    function decreaseStakedLiquidity(
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Check whether a position is staked in the gauge by a certain user
    /// @param depositor The address of the user
    /// @param tokenId The tokenId of the position
    /// @return Whether the position is staked in the gauge
    function stakedContains(address depositor, uint256 tokenId) external view returns (bool);

    /// @notice The amount of positions staked in the gauge by a certain user
    /// @param depositor The address of the user
    /// @return The amount of positions staked in the gauge
    function stakedLength(address depositor) external view returns (uint256);
}
