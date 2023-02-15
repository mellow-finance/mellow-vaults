// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2022
pragma solidity ^0.8.9;
import { IVersion } from "./IVersion.sol";

/// @title Credit Account
/// @notice Implements generic credit account logic:
///   - Holds collateral assets
///   - Stores general parameters: borrowed amount, cumulative index at open and block when it was initialized
///   - Transfers assets
///   - Executes financial orders by calling connected protocols on its behalf
///
///  More: https://dev.gearbox.fi/developers/credit/credit_account

interface ICrediAccountExceptions {
    /// @dev throws if the caller is not the connected Credit Manager
    error CallerNotCreditManagerException();

    /// @dev throws if the caller is not the factory
    error CallerNotFactoryException();
}

interface ICreditAccount is ICrediAccountExceptions, IVersion {
    /// @dev Called on new Credit Account creation.
    /// @notice Initialize is used instead of constructor, since the contract is cloned.
    function initialize() external;

    /// @dev Connects this credit account to a Credit Manager. Restricted to the account factory (owner) only.
    /// @param _creditManager Credit manager address
    /// @param _borrowedAmount The amount borrowed at Credit Account opening
    /// @param _cumulativeIndexAtOpen The interest index at Credit Account opening
    function connectTo(
        address _creditManager,
        uint256 _borrowedAmount,
        uint256 _cumulativeIndexAtOpen
    ) external;

    /// @dev Updates borrowed amount and cumulative index. Restricted to the currently connected Credit Manager.
    /// @param _borrowedAmount The amount currently lent to the Credit Account
    /// @param _cumulativeIndexAtOpen New cumulative index to calculate interest from
    function updateParameters(
        uint256 _borrowedAmount,
        uint256 _cumulativeIndexAtOpen
    ) external;

    /// @dev Removes allowance for a token to a 3rd-party contract. Restricted to factory only.
    /// @param token ERC20 token to remove allowance for.
    /// @param targetContract Target contract to revoke allowance to.
    function cancelAllowance(address token, address targetContract) external;

    /// @dev Transfers tokens from the credit account to a provided address. Restricted to the current Credit Manager only.
    /// @param token Token to be transferred from the Credit Account.
    /// @param to Address of the recipient.
    /// @param amount Amount to be transferred.
    function safeTransfer(
        address token,
        address to,
        uint256 amount
    ) external;

    /// @dev Returns the principal amount borrowed from the pool
    function borrowedAmount() external view returns (uint256);

    /// @dev Returns the cumulative interest index since the last Credit Account's debt update
    function cumulativeIndexAtOpen() external view returns (uint256);

    /// @dev Returns the block at which the contract was last taken from the factory
    function since() external view returns (uint256);

    /// @dev Returns the address of the currently connected Credit Manager
    function creditManager() external view returns (address);

    /// @dev Address of the Credit Account factory
    function factory() external view returns (address);

    /// @dev Executes a call to a 3rd party contract with provided data. Restricted to the current Credit Manager only.
    /// @param destination Contract address to be called.
    /// @param data Data to call the contract with.
    function execute(address destination, bytes memory data)
        external
        returns (bytes memory);
}