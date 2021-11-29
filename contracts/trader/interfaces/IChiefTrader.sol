// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../../interfaces/IProtocolGovernance.sol";

interface IChiefTrader {
    /// @notice ProtocolGovernance
    /// @return the address of the protocol governance contract
    function protocolGovernance() external view returns (address);

    /// @return The list of trader ids
    function traders() external view returns (address[] memory);

    /// @return Count of traders
    function tradersCount() external view returns (uint256);

    /// @notice Add new trader
    /// @param traderAddress the address of the trader
    function addTrader(address traderAddress) external;
}
