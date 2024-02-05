// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// Inheritance
import "./Owned.sol";

// https://github.com/Synthetixio/synthetix/blob/v2.98.2/contracts/RewardsDistributionRecipient.sol
abstract contract RewardsDistributionRecipient is Owned {
    address public rewardsDistribution;

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Caller is not RewardsDistribution contract");
        _;
    }

    function setRewardsDistribution(address _rewardsDistribution) external onlyOwner {
        rewardsDistribution = _rewardsDistribution;
    }
}
