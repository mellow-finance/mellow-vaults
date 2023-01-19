// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "./IAlgebraPoolImmutables.sol";
import "./IAlgebraPoolState.sol";
import "./IAlgebraPoolDerivedState.sol";

/**
 * @title The interface for a Algebra Pool
 * @dev The pool interface is broken up into many smaller pieces.
 * Credit to Uniswap Labs under GPL-2.0-or-later license:
 * https://github.com/Uniswap/v3-core/tree/main/contracts/interfaces
 */
interface IAlgebraPool is IAlgebraPoolImmutables, IAlgebraPoolState, IAlgebraPoolDerivedState {
    // used only for combining interfaces
}
