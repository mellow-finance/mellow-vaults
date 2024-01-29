// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../strategies/BalancerVaultStrategy.sol";

contract BalancerVaultStrategyHelper {
    function getRewardAmounts(BalancerVaultStrategy strategy)
        public
        returns (
            address[] memory rewardTokens,
            uint256[] memory balances,
            uint8[] memory decimals
        )
    {
        IBalancerV2Vault subvault = strategy.subvault();
        try subvault.claimBalancerRewardToken() returns (uint256) {} catch {}
        try subvault.claimRewards() {} catch {}
        rewardTokens = strategy.rewardTokens();
        balances = new uint256[](rewardTokens.length);
        decimals = new uint8[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            balances[i] = IERC20(rewardTokens[i]).balanceOf(address(strategy));
            decimals[i] = IERC20Metadata(rewardTokens[i]).decimals();
        }
    }
}
