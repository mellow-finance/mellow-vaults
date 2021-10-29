export default class Exceptions {
    static readonly GOVERNANCE_OR_DELEGATE: string = "GD";
    static readonly NULL: string = "NULL";
    static readonly TIMESTAMP: string = "TS";
    static readonly GOVERNANCE_OR_DELEGATE_ADDRESS_ZERO: string = "ZMG";
    static readonly EMPTY_PARAMS: string = "P0";
    static readonly ADMIN: string = "ADM";
    static readonly ADMIN_ADDRESS_ZERO: string = "ZADM";
    static readonly VAULT_FACTORY_ADDRESS_ZERO: string = "ZVF";
    static readonly APPROVED_OR_OWNER: string = "IO";
    static readonly INCONSISTENT_LENGTH: string = "L";
    static readonly SORTED_AND_UNIQUE: string = "SAU";
    static readonly ERC20_INSUFFICIENT_BALANCE: string =
        "ERC20: transfer amount exceeds balance";
    static readonly VALID_PULL_DESTINATION: string = "INTRA";
    static readonly CONTRACT_REQUIRED: string = "C";
}
// TODO: Remove outdated exceptions
