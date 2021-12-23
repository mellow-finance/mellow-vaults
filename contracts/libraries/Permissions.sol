// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

library Permissions {
    uint64 constant ERC20_TRANSFER_PERMISSION = 1 << 1;
    uint64 constant ERC20_OPERATE_PERMISSION = 1 << 2;
    uint64 constant ERC20_VAULT_TOKEN_PERMISSION = 1 << 3;
    uint64 constant CLAIM_PERMISSION = 1 << 4;
    uint64 constant VAULT_GOVERNANCE_PERMISSION = 1 << 5;

    function validatePermission(uint64 permission) internal pure returns (bool) {
        return permission == ERC20_TRANSFER_PERMISSION ||
            permission == ERC20_OPERATE_PERMISSION ||
            permission == ERC20_VAULT_TOKEN_PERMISSION ||
            permission == CLAIM_PERMISSION ||
            permission == VAULT_GOVERNANCE_PERMISSION ||
            permission == 0;
    }
}
