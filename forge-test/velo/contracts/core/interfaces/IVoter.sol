// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import {IVotingEscrow} from "forge-test/velo/contracts/core/interfaces/IVotingEscrow.sol";

interface IVoter {
    function ve() external view returns (IVotingEscrow);

    function vote(
        uint256 _tokenId,
        address[] calldata _poolVote,
        uint256[] calldata _weights
    ) external;

    function gauges(address _pool) external view returns (address);

    function gaugeToFees(address _gauge) external view returns (address);

    function gaugeToBribes(address _gauge) external view returns (address);

    function createGauge(address _poolFactory, address _pool) external returns (address);

    function distribute(address gauge) external;

    /// @dev Utility to distribute to gauges of pools in array.
    /// @param _gauges Array of gauges to distribute to.
    function distribute(address[] memory _gauges) external;

    function isAlive(address _gauge) external view returns (bool);

    function killGauge(address _gauge) external;

    function emergencyCouncil() external view returns (address);

    /// @notice Claim fees for a given NFT.
    /// @dev Utility to help batch fee claims.
    /// @param _fees    Array of FeesVotingReward contracts to collect from.
    /// @param _tokens  Array of tokens that are used as fees.
    /// @param _tokenId Id of veNFT that you wish to claim fees for.
    function claimFees(
        address[] memory _fees,
        address[][] memory _tokens,
        uint256 _tokenId
    ) external;
}
