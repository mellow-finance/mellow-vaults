// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/perp/IPerpInternalVault.sol";
import "../external/perp/IClearingHouse.sol";
import "../external/perp/IBaseToken.sol";
import "../external/perp/IAccountBalance.sol";
import "../external/univ3/IUniswapV3Pool.sol";

interface IPerpVault is IIntegrationVault {
    struct Options {
        uint256 deadline;
    }

    struct PositionInfo {
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
    }

    function baseToken() external view returns (address);

    function vault() external view returns (IPerpInternalVault);

    function clearingHouse() external view returns (IClearingHouse);

    function pool() external view returns (IUniswapV3Pool);

    function accountBalance() external view returns (IAccountBalance);

    function isPositionOpened() external view returns (bool);

    function position() external view returns (PositionInfo memory);

    function usdc() external view returns (address);

    function initialize(
        uint256 nft_,
        address baseToken_,
        uint256 leverageMultiplierD_
    ) external;

    function openUniPosition(
        int24 lowerTick,
        int24 upperTick,
        uint256[] memory minVTokenAmounts, /*maybe not needed*/ /*usdc, second token*/
        uint256 deadline
    ) external returns (uint128 liquidityAdded);

    function closeUniPosition(
        uint256[] memory minVTokenAmounts, /*maybe not needed*/
        uint256 deadline
    ) external;

    function getAccountValue() external view returns (uint256 value);

    function updateLeverage(uint256 newLeverageMultiplierD_, uint256 deadline) external;
}