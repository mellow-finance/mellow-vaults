// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/perp/IPerpInternalVault.sol";
import "../external/perp/IClearingHouse.sol";
import "../external/perp/IBaseToken.sol";
import "../external/perp/IAccountBalance.sol";
import "../external/univ3/IUniswapV3Pool.sol";

interface IPerpVault is IIntegrationVault {
    /// @notice Options for operations with Uni position
    /// @param deadline The restriction on when the transaction should be executed, otherwise, it fails
    struct Options {
        uint256 deadline;
    }

    /// @notice Main information, representing UniV3 position
    /// @param lowerTick The lower tick boundary of the position
    /// @param upperTick The upper tick boundary of the position
    /// @param liquidity The liquidity of the position
    struct PositionInfo {
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
    }

    // -------------------  EXTERNAL, VIEW  -------------------

    /// @notice Returns the base token, the virtual underlying asset that a user is trading with
    /// @return address Base token contract address
    function baseToken() external view returns (address);

    /// @notice Returns the Perp Protocol internal vault, which is used for deposits/withdrawals and stores all users` collateral
    /// @return IPerpInternalVault Perp Internal Vault contract interface
    function vault() external view returns (IPerpInternalVault);

    /// @notice Returns the Perp Protocol Clearing House, which is the manager of all the positions in PerpV2
    /// @return IClearingHouse Perp Clearing House contract interface
    function clearingHouse() external view returns (IClearingHouse);

    /// @notice Returns UniswapV3 pool, which is the underlying pool with vUSDC / baseToken token pair and 0,3% fees
    /// @return IUniswapV3Pool Uniswap pool interface, which is used in your Perp position
    function pool() external view returns (IUniswapV3Pool);

    /// @notice Returns Perp Protocol Account Balance, which records most of the traders` balances (margin ratio, position size, position value)
    /// @return IAccountBalance Perp Protocol Account Balance interface
    function accountBalance() external view returns (IAccountBalance);

    /// @notice Flag, representing the status of Uni position (open / close)
    /// @return bool Returns true is position is opened, else - false
    function isPositionOpened() external view returns (bool);

    /// @notice Returns the main information about the Uni position (tick boundaries and total liquidity)
    /// @return PositionInfo Information stored for each user's Uni position, packed into a struct
    function position() external view returns (PositionInfo memory);

    /// @notice Address of the USDC used as a collateral
    /// @return address Address of the USDC contract
    function usdc() external view returns (address);

    /// @notice Returns how much your position is worth (nominated in USDC)
    /// @return value Position capital estimated in USDC
    function getAccountValue() external view returns (uint256 value);

    // -------------------  EXTERNAL, MUTATING  -------------------

    /// @notice Initialized a new contract
    /// @dev Can only be initialized by vault governance
    /// @param nft_ NFT of the vault in the VaultRegistry
    /// @param baseToken_ Address of the virtual underlying asset that a user is trading with
    /// @param leverageMultiplierD_ The vault capital leverage multiplier (multiplied by DENOMINATOR)
    function initialize(
        uint256 nft_,
        address baseToken_,
        uint256 leverageMultiplierD_
    ) external;

    /// @notice Opens a position on UniswapV3 pool using the given tick boundaries, and to provide liquidity to the pool
    /// @dev If a position has already been opened, it reverts
    /// @param lowerTick The lower tick boundary of the position
    /// @param upperTick The upper tick boundary of the position
    /// @param minVTokenAmounts The minimum amount of base and quote tokens, which user wants to provide
    /// @param deadline The restriction on when the addLiquidily transaction should be executed, otherwise, it fails
    /// @return liquidityAdded The amount of the provided liquidity
    function openUniPosition(
        int24 lowerTick,
        int24 upperTick,
        uint256[] memory minVTokenAmounts, /*maybe not needed*/ /*usdc, second token*/
        uint256 deadline
    ) external returns (uint128 liquidityAdded);

    /// @notice Closes a position on UniswapV3 pool and remove all the provided liquidity
    /// @dev If a position has not been opened, it reverts
    /// @param minVTokenAmounts The minimum amount of base and quote tokens, which user wants to remove
    /// @param deadline The restriction on when the removeLiquidity transaction should be executed, otherwise, it fails
    function closeUniPosition(
        uint256[] memory minVTokenAmounts, /*maybe not needed*/
        uint256 deadline
    ) external;

    /// @notice Updates vault capital leverage multiplier (multiplied by DENOMINATOR)
    /// @param newLeverageMultiplierD_ The new vault capital leverage multiplier (multiplied by DENOMINATOR)
    /// @param deadline The restriction on when the transaction should be executed, otherwise, it fails
    function updateLeverage(uint256 newLeverageMultiplierD_, uint256 deadline) external;
}