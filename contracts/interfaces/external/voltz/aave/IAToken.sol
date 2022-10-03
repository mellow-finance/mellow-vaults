// SPDX-License-Identifier: Apache-2.0

pragma solidity =0.8.9;

import "../IERC20Minimal.sol";

/**
 * @title Minimal interface used by Voltz to represent an Aave AToken
 *
 * @author Voltz
 */
interface IAToken {

  /**
   * @dev Burns aTokens from `user` and sends the equivalent amount of underlying to `receiverOfUnderlying`
   * @param user The owner of the aTokens, getting them burned
   * @param receiverOfUnderlying The address that will receive the underlying
   * @param amount The amount being burned
   * @param index The new liquidity index of the reserve
   **/
  function burn(
    address user,
    address receiverOfUnderlying,
    uint256 amount,
    uint256 index
  ) external;
}