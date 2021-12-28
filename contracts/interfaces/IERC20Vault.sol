// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";
import "../trader/interfaces/ITrader.sol";

interface IERC20Vault is ITrader, IIntegrationVault {}
