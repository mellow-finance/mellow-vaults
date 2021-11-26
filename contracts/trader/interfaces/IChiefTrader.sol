// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../../interfaces/IProtocolGovernance.sol";

interface IChiefTrader {
    /// @notice Swap type
    enum SwapType {
        EXACT_INPUT_SINGLE,
        EXACT_OUTPUT_SINGLE,
        EXACT_INPUT_MULTIHOP,
        EXACT_OUTPUT_MULTIHOP
    }

    /// @notice ProtocolGovernance
    /// @return the address of the protocol governance contract
    function protocolGovernance() external view returns (address);

    /// @notice Get traderId by traderAddress
    /// @param traderAddress the address of the trader
    /// @return the address of the protocol governance contract
    function traderIdByAddress(address traderAddress) external view returns (uint256);

    /// @notice Get traderAddress by traderId
    /// @param traderId the id of the trader
    /// @return the address of the trader
    function traderAddressById(uint256 traderId) external view returns (address);

    /// @return the list of trader ids
    function traders() external view returns (uint256[] memory);

    /// @notice Add new trader
    /// @param traderAddress the address of the trader
    function addTrader(address traderAddress) external;

    /// @notice Remove trader by address
    /// @param traderAddress the address of the trader
    function removeTraderByAddress(address traderAddress) external;

    /// @notice Remove trader by id
    /// @param traderId the id of the trader
    function removeTraderById(uint256 traderId) external;

    /// @notice Swap
    /// @param traderId Id of the trader to perform swap
    /// @param input Address of the input token
    /// @param output Address of the output token
    /// @param amount Amount to be swapped (in input or in output token)
    /// @param swapType Type of the swap (e.g. EXACT_INPUT_SINGLE, ...)
    /// @param options Protocol-specific options
    /// @return The amount of input or output token spent
    function trade(
        uint256 traderId,
        address input,
        address output,
        uint256 amount,
        SwapType swapType,
        bytes calldata options
    ) external returns (uint256);
}
