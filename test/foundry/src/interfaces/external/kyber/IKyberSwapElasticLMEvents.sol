// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IKyberSwapElasticLMEvents {
  event AddPool(
    uint256 indexed pId,
    address poolAddress,
    uint32 startTime,
    uint32 endTime,
    uint32 vestingDuration,
    uint256 feeTarget
  );

  event RenewPool(
    uint256 indexed pid,
    uint32 startTime,
    uint32 endTime,
    uint32 vestingDuration,
    uint256 feeTarget
  );

  event Deposit(address sender, uint256 indexed nftId);

  event Withdraw(address sender, uint256 indexed nftId);

  event Join(uint256 indexed nftId, uint256 indexed pId, uint256 indexed liq);

  event Exit(address to, uint256 indexed nftId, uint256 indexed pId, uint256 indexed liq);

  event SyncLiq(uint256 indexed nftId, uint256 indexed pId, uint256 indexed liq);

  event Harvest(address to, address reward, uint256 indexed amount);

  event EmergencyEnabled();

  event EmergencyWithdrawForOwner(address reward, uint256 indexed amount);

  event EmergencyWithdraw(address sender, uint256 indexed nftId);
}