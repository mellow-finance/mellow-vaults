// SPDX-License-Identifier: Apache-2.0

pragma solidity =0.8.9;

// Subset of https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol
interface ICToken {

    /**
     * @notice Calculates the exchange rate from the underlying to the CToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals)
     */
  function exchangeRateStored() external view returns (uint256);

    /**
     * @notice Accrue interest then return the up-to-date exchange rate
     * @return Calculated exchange rate, scaled by 1 * 10^(18 - 8 + Underlying Token Decimals)
     */
  function exchangeRateCurrent() external returns (uint256);

  function redeemUnderlying(uint redeemAmount) external returns (uint);

      /**
     * @notice Underlying asset for this CToken
     */
  function underlying() external view returns (address);
}