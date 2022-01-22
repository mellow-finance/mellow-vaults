//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @notice Stores permission ids for addresses
library PermissionIdsLibrary {
    // The msg.sender is allowed to register vault
    uint8 constant REGISTER_VAULT = 0;
    // The token is allowed to be transfered by vault
    uint8 constant ERC20_TRANSFER = 1;
    // The token is allowed to be added to vault
    uint8 constant ERC20_VAULT_TOKEN = 2;
    // The msg.sender is allowed to create vaults
    uint8 constant CREATE_VAULT = 3;
    // The pool is allowed to be used for swap
    uint8 constant SWAP = 4;
}
