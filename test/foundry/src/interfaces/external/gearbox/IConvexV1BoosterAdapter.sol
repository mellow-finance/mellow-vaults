// SPDX-License-Identifier: GPL-2.0-or-later
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Holdings, 2021
pragma solidity ^0.8.9;

import { IAdapter } from "./helpers/IAdapter.sol";
import { IBooster } from "./helpers/convex/IBooster.sol";

interface IConvexV1BoosterAdapter is IAdapter, IBooster {
    /// @dev Scans the Credit Manager's allowed contracts for Convex pool
    ///      adapters and adds the corresponding phantom tokens to an internal mapping
    /// @notice Admin function. The mapping is used to determine an output token from the
    ///         pool's pid, when deposit is called with stake == true
    function updateStakedPhantomTokensMap() external;
}