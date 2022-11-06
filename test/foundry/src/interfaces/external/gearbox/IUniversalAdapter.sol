// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.9;

import { IAdapter } from "./helpers/IAdapter.sol";

struct RevocationPair {
    address spender;
    address token;
}

interface IUniversalAdapterExceptions {
    /// @dev Thrown when the Credit Account of msg.sender does not match the provided expected account
    error UnexpectedCreditAccountException(address expected, address actual);
}

interface IUniversalAdapter is IAdapter, IUniversalAdapterExceptions {
    /// @dev Sets allowances to zero for provided spender/token pairs, for msg.sender's CA
    /// @param revocations Pairs of spenders/tokens to revoke allowances for
    function revokeAdapterAllowances(RevocationPair[] calldata revocations)
        external;

    /// @dev Sets allowances to zero for the provided spender/token pairs
    /// Checks that the msg.sender CA matches the expected account, since
    /// provided revocations are specific to a particular CA
    /// @param revocations Pairs of spenders/tokens to revoke allowances for
    /// @param expectedCreditAccount Credit account that msg.sender is expected to have
    function revokeAdapterAllowances(
        RevocationPair[] calldata revocations,
        address expectedCreditAccount
    ) external;

    function withdraw(address token, uint256 amount) external;

}