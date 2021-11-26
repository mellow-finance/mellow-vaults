// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../interfaces/IProtocolGovernance.sol";

interface IMasterTrader {
    /// @notice Swap type
    enum SwapType {
        EXACT_INPUT_SINGLE,
        EXACT_OUTPUT_SINGLE,
        EXACT_INPUT_MULTIHOP,
        EXACT_OUTPUT_MULTIHOP
    }

    /// @return the address of the protocol governance contract
    function protocolGovernance() external view returns (address);

    /// @param traderAddress the address of the trader
    /// @return the address of the protocol governance contract
    function traderIdByAddress(address traderAddress) external view returns (uint256);

    function traderAddressById(uint256) external view returns (address);

    function traders() external view returns (uint256[] memory);

    function addTrader(address) external;

    function removeTraderByAddress(address) external;

    function removeTraderById(uint256) external;

    function trade(
        uint256 traderId,
        address input,
        address output,
        uint256 amount,
        SwapType swapType,
        bytes calldata options
    ) external returns (uint256);
}
