// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../external/perp/IPerpInternalVault.sol";
import "../external/perp/IClearingHouse.sol";
import "../external/perp/IBaseToken.sol";
import "../external/perp/IAccountBalance.sol";

interface IPerpFuturesVault is IIntegrationVault {
    struct Options {
        uint256 deadline;
    }

    function baseToken() external view returns (address);

    function vault() external view returns (IPerpInternalVault);

    function clearingHouse() external view returns (IClearingHouse);

    function accountBalance() external view returns (IAccountBalance);

    function usdc() external view returns (address);

    function initialize(
        uint256 nft_,
        address baseToken_,
        uint256 leverageMultiplierD_,
        bool isLongBaseToken_
    ) external;

    function getAccountValue() external view returns (uint256 value);

    function updateLeverage(uint256 newLeverageMultiplierD_, bool isLongBaseToken_, uint256 deadline) external;

    function adjustPosition(uint256 deadline) external;

    function closePosition(uint256 deadline) external;
}