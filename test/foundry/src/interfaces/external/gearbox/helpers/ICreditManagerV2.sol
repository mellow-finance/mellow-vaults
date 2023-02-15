// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.9;

import { IPriceOracleV2 } from "./IPriceOracle.sol";
import { IVersion } from "./IVersion.sol";

enum ClosureAction {
    CLOSE_ACCOUNT,
    LIQUIDATE_ACCOUNT,
    LIQUIDATE_EXPIRED_ACCOUNT,
    LIQUIDATE_PAUSED
}

interface ICreditManagerV2Events {
    /// @dev Emits when a call to an external contract is made through the Credit Manager
    event ExecuteOrder(address indexed borrower, address indexed target);

    /// @dev Emits when a configurator is upgraded
    event NewConfigurator(address indexed newConfigurator);
}

interface ICreditManagerV2Exceptions {
    /// @dev Thrown if an access-restricted function is called by an address that is not
    ///      the connected Credit Facade, or an allowed adapter
    error AdaptersOrCreditFacadeOnlyException();

    /// @dev Thrown if an access-restricted function is called by an address that is not
    ///      the connected Credit Facade
    error CreditFacadeOnlyException();

    /// @dev Thrown if an access-restricted function is called by an address that is not
    ///      the connected Credit Configurator
    error CreditConfiguratorOnlyException();

    /// @dev Thrown on attempting to open a Credit Account for or transfer a Credit Account
    ///      to the zero address or an address that already owns a Credit Account
    error ZeroAddressOrUserAlreadyHasAccountException();

    /// @dev Thrown on attempting to execute an order to an address that is not an allowed
    ///      target contract
    error TargetContractNotAllowedException();

    /// @dev Thrown on failing a full collateral check after an operation
    error NotEnoughCollateralException();

    /// @dev Thrown on attempting to receive a token that is not a collateral token
    ///      or was forbidden
    error TokenNotAllowedException();

    /// @dev Thrown if an attempt to approve a collateral token to a target contract failed
    error AllowanceFailedException();

    /// @dev Thrown on attempting to perform an action for an address that owns no Credit Account
    error HasNoOpenedAccountException();

    /// @dev Thrown on attempting to add a token that is already in a collateral list
    error TokenAlreadyAddedException();

    /// @dev Thrown on configurator attempting to add more than 256 collateral tokens
    error TooManyTokensException();

    /// @dev Thrown if more than the maximal number of tokens were enabled on a Credit Account,
    ///      and there are not enough unused token to disable
    error TooManyEnabledTokensException();

    /// @dev Thrown when a reentrancy into the contract is attempted
    error ReentrancyLockException();
}

/// @notice All Credit Manager functions are access-restricted and can only be called
///         by the Credit Facade or allowed adapters. Users are not allowed to
///         interact with the Credit Manager directly
interface ICreditManagerV2 is
    ICreditManagerV2Events,
    ICreditManagerV2Exceptions,
    IVersion
{
    //
    // CREDIT ACCOUNT MANAGEMENT
    //

    ///  @dev Opens credit account and borrows funds from the pool.
    /// - Takes Credit Account from the factory;
    /// - Requests the pool to lend underlying to the Credit Account
    ///
    /// @param borrowedAmount Amount to be borrowed by the Credit Account
    /// @param onBehalfOf The owner of the newly opened Credit Account
    function openCreditAccount(uint256 borrowedAmount, address onBehalfOf)
        external
        returns (address);

    ///  @dev Closes a Credit Account - covers both normal closure and liquidation
    /// - Checks whether the contract is paused, and, if so, if the payer is an emergency liquidator.
    ///   Only emergency liquidators are able to liquidate account while the CM is paused.
    ///   Emergency liquidations do not pay a liquidator premium or liquidation fees.
    /// - Calculates payments to various recipients on closure:
    ///    + Computes amountToPool, which is the amount to be sent back to the pool.
    ///      This includes the principal, interest and fees, but can't be more than
    ///      total position value
    ///    + Computes remainingFunds during liquidations - these are leftover funds
    ///      after paying the pool and the liquidator, and are sent to the borrower
    ///    + Computes protocol profit, which includes interest and liquidation fees
    ///    + Computes loss if the totalValue is less than borrow amount + interest
    /// - Checks the underlying token balance:
    ///    + if it is larger than amountToPool, then the pool is paid fully from funds on the Credit Account
    ///    + else tries to transfer the shortfall from the payer - either the borrower during closure, or liquidator during liquidation
    /// - Send assets to the "to" address, as long as they are not included into skipTokenMask
    /// - If convertWETH is true, the function converts WETH into ETH before sending
    /// - Returns the Credit Account back to factory
    ///
    /// @param borrower Borrower address
    /// @param closureActionType Whether the account is closed, liquidated or liquidated due to expiry
    /// @param totalValue Portfolio value for liqution, 0 for ordinary closure
    /// @param payer Address which would be charged if credit account has not enough funds to cover amountToPool
    /// @param to Address to which the leftover funds will be sent
    /// @param skipTokenMask Tokenmask contains 1 for tokens which needed to be skipped for sending
    /// @param convertWETH If true converts WETH to ETH
    function closeCreditAccount(
        address borrower,
        ClosureAction closureActionType,
        uint256 totalValue,
        address payer,
        address to,
        uint256 skipTokenMask,
        bool convertWETH
    ) external returns (uint256 remainingFunds);

    /// @dev Manages debt size for borrower:
    ///
    /// - Increase debt:
    ///   + Increases debt by transferring funds from the pool to the credit account
    ///   + Updates the cumulative index to keep interest the same. Since interest
    ///     is always computed dynamically as borrowedAmount * (cumulativeIndexNew / cumulativeIndexOpen - 1),
    ///     cumulativeIndexOpen needs to be updated, as the borrow amount has changed
    ///
    /// - Decrease debt:
    ///   + Repays debt partially + all interest and fees accrued thus far
    ///   + Updates cunulativeIndex to cumulativeIndex now
    ///
    /// @param creditAccount Address of the Credit Account to change debt for
    /// @param amount Amount to increase / decrease the principal by
    /// @param increase True to increase principal, false to decrease
    /// @return newBorrowedAmount The new debt principal
    function manageDebt(
        address creditAccount,
        uint256 amount,
        bool increase
    ) external returns (uint256 newBorrowedAmount);

    /// @dev Adds collateral to borrower's credit account
    /// @param payer Address of the account which will be charged to provide additional collateral
    /// @param creditAccount Address of the Credit Account
    /// @param token Collateral token to add
    /// @param amount Amount to add
    function addCollateral(
        address payer,
        address creditAccount,
        address token,
        uint256 amount
    ) external;

    /// @dev Transfers Credit Account ownership to another address
    /// @param from Address of previous owner
    /// @param to Address of new owner
    function transferAccountOwnership(address from, address to) external;

    /// @dev Requests the Credit Account to approve a collateral token to another contract.
    /// @param borrower Borrower's address
    /// @param targetContract Spender to change allowance for
    /// @param token Collateral token to approve
    /// @param amount New allowance amount
    function approveCreditAccount(
        address borrower,
        address targetContract,
        address token,
        uint256 amount
    ) external;

    /// @dev Requests a Credit Account to make a low-level call with provided data
    /// This is the intended pathway for state-changing interactions with 3rd-party protocols
    /// @param borrower Borrower's address
    /// @param targetContract Contract to be called
    /// @param data Data to pass with the call
    function executeOrder(
        address borrower,
        address targetContract,
        bytes memory data
    ) external returns (bytes memory);

    //
    // COLLATERAL VALIDITY AND ACCOUNT HEALTH CHECKS
    //

    /// @dev Enables a token on a Credit Account, including it
    /// into account health and total value calculations
    /// @param creditAccount Address of a Credit Account to enable the token for
    /// @param token Address of the token to be enabled
    function checkAndEnableToken(address creditAccount, address token) external;

    /// @dev Optimized health check for individual swap-like operations.
    /// @notice Fast health check assumes that only two tokens (input and output)
    ///         participate in the operation and computes a % change in weighted value between
    ///         inbound and outbound collateral. The cumulative negative change across several
    ///         swaps in sequence cannot be larger than feeLiquidation (a fee that the
    ///         protocol is ready to waive if needed). Since this records a % change
    ///         between just two tokens, the corresponding % change in TWV will always be smaller,
    ///         which makes this check safe.
    ///         More details at https://dev.gearbox.fi/docs/documentation/risk/fast-collateral-check#fast-check-protection
    /// @param creditAccount Address of the Credit Account
    /// @param tokenIn Address of the token spent by the swap
    /// @param tokenOut Address of the token received from the swap
    /// @param balanceInBefore Balance of tokenIn before the operation
    /// @param balanceOutBefore Balance of tokenOut before the operation
    function fastCollateralCheck(
        address creditAccount,
        address tokenIn,
        address tokenOut,
        uint256 balanceInBefore,
        uint256 balanceOutBefore
    ) external;

    /// @dev Performs a full health check on an account, summing up
    /// value of all enabled collateral tokens
    /// @param creditAccount Address of the Credit Account to check
    function fullCollateralCheck(address creditAccount) external;

    /// @dev Checks that the number of enabled tokens on a Credit Account
    ///      does not violate the maximal enabled token limit and tries
    ///      to disable unused tokens if it does
    /// @param creditAccount Account to check enabled tokens for
    function checkAndOptimizeEnabledTokens(address creditAccount) external;

    /// @dev Disables a token on a credit account
    /// @notice Usually called by adapters to disable spent tokens during a multicall,
    ///         but can also be called separately from the Credit Facade to remove
    ///         unwanted tokens
    function disableToken(address creditAccount, address token) external;

    //
    // GETTERS
    //

    /// @dev Returns the address of a borrower's Credit Account, or reverts if there is none.
    /// @param borrower Borrower's address
    function getCreditAccountOrRevert(address borrower)
        external
        view
        returns (address);

    /// @dev Computes amounts that must be sent to various addresses before closing an account
    /// @param totalValue Credit Accounts total value in underlying
    /// @param closureActionType Type of account closure
    ///        * CLOSE_ACCOUNT: The account is healthy and is closed normally
    ///        * LIQUIDATE_ACCOUNT: The account is unhealthy and is being liquidated to avoid bad debt
    ///        * LIQUIDATE_EXPIRED_ACCOUNT: The account has expired and is being liquidated (lowered liquidation premium)
    ///        * LIQUIDATE_PAUSED: The account is liquidated while the system is paused due to emergency (no liquidation premium)
    /// @param borrowedAmount Credit Account's debt principal
    /// @param borrowedAmountWithInterest Credit Account's debt principal + interest
    /// @return amountToPool Amount of underlying to be sent to the pool
    /// @return remainingFunds Amount of underlying to be sent to the borrower (only applicable to liquidations)
    /// @return profit Protocol's profit from fees (if any)
    /// @return loss Protocol's loss from bad debt (if any)
    function calcClosePayments(
        uint256 totalValue,
        ClosureAction closureActionType,
        uint256 borrowedAmount,
        uint256 borrowedAmountWithInterest
    )
        external
        view
        returns (
            uint256 amountToPool,
            uint256 remainingFunds,
            uint256 profit,
            uint256 loss
        );

    /// @dev Calculates the debt accrued by a Credit Account
    /// @param creditAccount Address of the Credit Account
    /// @return borrowedAmount The debt principal
    /// @return borrowedAmountWithInterest The debt principal + accrued interest
    /// @return borrowedAmountWithInterestAndFees The debt principal + accrued interest and protocol fees
    function calcCreditAccountAccruedInterest(address creditAccount)
        external
        view
        returns (
            uint256 borrowedAmount,
            uint256 borrowedAmountWithInterest,
            uint256 borrowedAmountWithInterestAndFees
        );

    /// @dev Maps Credit Accounts to bit masks encoding their enabled token sets
    /// Only enabled tokens are counted as collateral for the Credit Account
    /// @notice An enabled token mask encodes an enabled token by setting
    ///         the bit at the position equal to token's index to 1
    function enabledTokensMap(address creditAccount)
        external
        view
        returns (uint256);

    /// @dev Maps the Credit Account to its current percentage drop across all swaps since
    ///      the last full check, in RAY format
    function cumulativeDropAtFastCheckRAY(address creditAccount)
        external
        view
        returns (uint256);

    /// @dev Returns the collateral token at requested index and its liquidation threshold
    /// @param id The index of token to return
    function collateralTokens(uint256 id)
        external
        view
        returns (address token, uint16 liquidationThreshold);

    /// @dev Returns the collateral token with requested mask and its liquidationThreshold
    /// @param tokenMask Token mask corresponding to the token
    function collateralTokensByMask(uint256 tokenMask)
        external
        view
        returns (address token, uint16 liquidationThreshold);

    /// @dev Total number of known collateral tokens.
    function collateralTokensCount() external view returns (uint256);

    /// @dev Returns the mask for the provided token
    /// @param token Token to returns the mask for
    function tokenMasksMap(address token) external view returns (uint256);

    /// @dev Bit mask encoding a set of forbidden tokens
    function forbiddenTokenMask() external view returns (uint256);

    /// @dev Maps allowed adapters to their respective target contracts.
    function adapterToContract(address adapter) external view returns (address);

    /// @dev Maps 3rd party contracts to their respective adapters
    function contractToAdapter(address targetContract)
        external
        view
        returns (address);

    /// @dev Address of the underlying asset
    function underlying() external view returns (address);

    /// @dev Address of the connected pool
    function pool() external view returns (address);

    /// @dev Address of the connected pool
    /// @notice [DEPRECATED]: use pool() instead.
    function poolService() external view returns (address);

    /// @dev A map from borrower addresses to Credit Account addresses
    function creditAccounts(address borrower) external view returns (address);

    /// @dev Address of the connected Credit Configurator
    function creditConfigurator() external view returns (address);

    /// @dev Address of WETH
    function wethAddress() external view returns (address);

    /// @dev Returns the liquidation threshold for the provided token
    /// @param token Token to retrieve the LT for
    function liquidationThresholds(address token)
        external
        view
        returns (uint16);

    /// @dev The maximal number of enabled tokens on a single Credit Account
    function maxAllowedEnabledTokenLength() external view returns (uint8);

    /// @dev Maps addresses to their status as emergency liquidator.
    /// @notice Emergency liquidators are trusted addresses
    /// that are able to liquidate positions while the contracts are paused,
    /// e.g. when there is a risk of bad debt while an exploit is being patched.
    /// In the interest of fairness, emergency liquidators do not receive a premium
    /// And are compensated by the Gearbox DAO separately.
    function canLiquidateWhilePaused(address) external view returns (bool);

    /// @dev Returns the fee parameters of the Credit Manager
    /// @return feeInterest Percentage of interest taken by the protocol as profit
    /// @return feeLiquidation Percentage of account value taken by the protocol as profit
    ///         during unhealthy account liquidations
    /// @return liquidationDiscount Multiplier that reduces the effective totalValue during unhealthy account liquidations,
    ///         allowing the liquidator to take the unaccounted for remainder as premium. Equal to (1 - liquidationPremium)
    /// @return feeLiquidationExpired Percentage of account value taken by the protocol as profit
    ///         during expired account liquidations
    /// @return liquidationDiscountExpired Multiplier that reduces the effective totalValue during expired account liquidations,
    ///         allowing the liquidator to take the unaccounted for remainder as premium. Equal to (1 - liquidationPremiumExpired)
    function fees()
        external
        view
        returns (
            uint16 feeInterest,
            uint16 feeLiquidation,
            uint16 liquidationDiscount,
            uint16 feeLiquidationExpired,
            uint16 liquidationDiscountExpired
        );

    /// @dev Address of the connected Credit Facade
    function creditFacade() external view returns (address);

    /// @dev Address of the connected Price Oracle
    function priceOracle() external view returns (IPriceOracleV2);

    /// @dev Address of the universal adapter
    function universalAdapter() external view returns (address);

    /// @dev Contract's version
    function version() external view returns (uint256);
}