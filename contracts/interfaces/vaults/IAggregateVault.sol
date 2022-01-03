// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IVault.sol";
import "./IVaultRoot.sol";
import "../trader/ITrader.sol";

interface IAggregateVault is IVault, IVaultRoot {}
