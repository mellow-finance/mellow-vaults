// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/perp/IPerpInternalVault.sol";
import "../external/perp/IClearingHouse.sol";
import "../external/perp/IBaseToken.sol";
import "../external/perp/IAccountBalance.sol";
import "../external/perp/IMarketRegistry.sol";

interface IPerpFuturesVault is IIntegrationVault {
    /// @notice Options for the operations with the position
    /// @param deadline The restriction on when the transaction should be executed, otherwise, it fails
    struct Options {
        uint256 deadline;
        uint256 oppositeAmountBound;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Returns the base token, the virtual underlying asset that a user is trading with
    /// @return address Base token contract address
    function baseToken() external view returns (address);

    /// @notice Returns the Perp Protocol internal vault, which is used for deposits/withdrawals and stores all the users` collateral
    /// @return IPerpInternalVault Perp Internal Vault contract interface
    function vault() external view returns (IPerpInternalVault);

    /// @notice Returns the Perp Protocol Clearing House, which is the manager of all the positions in PerpV2
    /// @return IClearingHouse Perp Clearing House contract interface
    function clearingHouse() external view returns (IClearingHouse);

    /// @notice Returns the Perp Protocol Account Balance, which records most of the traders` balances (margin ratio, position size, position value)
    /// @return IAccountBalance Perp Protocol Account Balance interface
    function accountBalance() external view returns (IAccountBalance);

    function marketRegistry() external view returns (IMarketRegistry);

    /// @notice The address of the USDC used as a collateral
    /// @return address The address of the USDC contract
    function usdc() external view returns (address);

    /// @notice Initialized a new contract
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param baseToken_ Address of the virtual underlying asset that a user is trading with
    /// @param leverageMultiplierD_ The vault capital leverage multiplier (multiplied by DENOMINATOR)
    /// @param isLongBaseToken_ True if the user`s base token position is a long one, else - false
    function initialize(
        uint256 nft_,
        address baseToken_,
        uint256 leverageMultiplierD_,
        bool isLongBaseToken_
    ) external;

    /// @notice Returns how much size in the open position is on your account (nominated in weis of a base token)
    /// @return value The position value estimated in of a base token
    function getPositionSize() external view returns (int256 value);

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Updates the vault capital leverage multiplier (multiplied by DENOMINATOR)
    /// @param newLeverageMultiplierD_ The new vault capital leverage multiplier (multiplied by DENOMINATOR)
    /// @param isLongBaseToken_ True if the user`s base token position is a long one, else - false
    /// @param deadline The restriction on when the transaction should be executed, otherwise, it fails
    function updateLeverage(uint256 newLeverageMultiplierD_, bool isLongBaseToken_, uint256 deadline, uint256 oppositeAmountBound) external;

    /// @notice Adjusts the current position to the capital multiplied by the current leverage multiplier. (capital nominated in USDC weis)
    /// @param deadline The restriction on when the transaction should be executed, otherwise, it fails
    function adjustPosition(uint256 deadline, uint256 oppositeAmountBound) external;

    /// @notice Closes the long/short position, taken by a user
    /// @param deadline The restriction on when the call to the ClearingHouse should be executed, otherwise, it fails
    function closePosition(uint256 deadline, uint256 oppositeAmountBound) external;
}