//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @notice Stores permission ids for addresses
library PermissionIdsLibrary {
    // The contract can be called for claiming liquidity mining rewards
    uint8 constant CLAIM = 0;
    // The msg.sender is allowed to register vault
    uint8 constant REGISTER_VAULT = 1;
    // The token is allowed to be transfered by vault
    uint8 constant ERC20_TRANSFER = 2;
    // The token is allowed to be swapped on dex by vault
    uint8 constant ERC20_SWAP = 3;
    // The token is allowed to be added to vault
    uint8 constant ERC20_VAULT_TOKEN = 4;
    // The msg.sender is allowed to create vaults
    uint8 constant CREATE_VAULT = 5;
    // The msg.sender is allowed to make deposits
    uint8 constant DEPOSIT = 6;
}
