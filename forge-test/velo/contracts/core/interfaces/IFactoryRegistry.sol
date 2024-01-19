// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFactoryRegistry {
    function approve(address poolFactory, address votingRewardsFactory, address gaugeFactory) external;

    function isPoolFactoryApproved(address poolFactory) external returns (bool);

    function factoriesToPoolFactory(address poolFactory)
        external
        returns (address votingRewardsFactory, address gaugeFactory);
}
