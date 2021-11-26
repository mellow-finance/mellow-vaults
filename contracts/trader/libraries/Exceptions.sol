// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

library Exceptions {
    string constant CHIEF_REQUIRED_EXCEPTION = "MS";
    string constant PROTOCOL_ADMIN_REQUIRED_EXCEPTION = "PA";
    string constant TRADER_ALREADY_REGISTERED_EXCEPTION = "TE";
    string constant TRADER_NOT_FOUND_EXCEPTION = "UT";
    string constant TRADE_FAILED_EXCEPTION = "TF";
    string constant VAULT_NOT_FOUND_EXCEPTION = "VF";
    string constant VAULT_TOKEN_REQUIRED_EXCEPTION = "VT";
    string constant AT_LEAST_STRATEGY_REQUIRED_EXCEPTION = "SR";
}
