// The msg.sender is allowed to register vault
export const REGISTER_VAULT = 0;
// The msg.sender is allowed to create vaults
export const CREATE_VAULT = 1;
// The token is allowed to be transfered by vault
export const ERC20_TRANSFER = 2;
// The token is allowed to be added to vault
export const ERC20_VAULT_TOKEN = 3;
// Trusted protocols that are allowed to be approved of vault ERC20 tokens by any strategy
export const ERC20_APPROVE = 4;
// Trusted protocols that are allowed to be approved of vault ERC20 tokens by trusted strategy
export const ERC20_APPROVE_RESTRICTED = 5;
// Strategy allowed using restricted API
export const TRUSTED_STRATEGY = 6;
