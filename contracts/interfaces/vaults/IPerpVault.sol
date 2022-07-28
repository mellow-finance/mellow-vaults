// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IIntegrationVault.sol";

interface IPerpVault is IIntegrationVault {
    struct Options {
        uint256 deadline;
    }
}