import { BytesLike } from "@ethersproject/bytes";
import { Contract } from "@ethersproject/contracts";

export type Address = string;

export type IERC20 = Address;
export type IVaultManager = Address;
export type IVaultFactory = Address;
export type IVaultGovernance = Address;
export type IVaultGovernanceFactory = Address;
export type IProtocolGovernance = Address;
export type IGatewayVaultManager = Address;

export type ERC20 = Contract;
export type ERC20Vault = Contract;
export type ERC20VaultManager = Contract;
export type ERC20VaultFactory = Contract;
export type ProtocolGovernance = Contract;
export type VaultManagerGovernance = Contract;
export type VaultGovernanceFactory = Contract;
export type VaultGovernance = Contract;

export type ProtocolGovernance_constructorArgs = {
    admin: Address
};

export type ProtocolGovernance_Params = {
    maxTokensPerVault: number,
    governanceDelay: number,
    strategyPerformanceFee: number,
    protocolPerformanceFee: number,
    protocolExitFee: number,
    protocolTreasury: Address,
    gatewayVaultManager: IGatewayVaultManager,
}

export type VaultGovernanceFactory_constructorArgs = {
    tokens: Address[],
    manager: IVaultManager,
    treasury: Address,
    admin: Address
};

/**
 * @dev creates IVault
 */
export type ERC20VaultFactory_deployVault = {
    vaultGovernance: IVaultGovernance,
    options: BytesLike
};
export type ERC20Vault_constructorArgs = ERC20VaultFactory_deployVault;

export type ERC20VaultManager_constructorArgs = {
    name: string,
    symbol: string,
    factory: IVaultFactory,
    governanceFactory: IVaultGovernanceFactory,
    permissionless: boolean,
    governance: IProtocolGovernance
};
/**
 * @dev creates IVault
 */
export type ERC20VaultManager_createVault = {
    tokens: IERC20[],
    strategyTreasury: Address,
    admin: Address,
    options: BytesLike
};

export type VaultManagerGovernance_constructorArgs = {
    permissionless: boolean,
    protocolGovernance: IProtocolGovernance,
    factory: IVaultFactory,
    governanceFactory: IVaultGovernanceFactory
};

/**
 * @dev creates IVaultGovernance
 */
export type VaultGovernanceFactory_deployVaultGovernance = {
    tokens: Address[],
    manager: IVaultManager,
    treasury: Address,
    admin: Address
};
export type VaultGovernance_constructorArgs = VaultGovernanceFactory_deployVaultGovernance;

export type ERC20Test_constructorArgs = {
    name: string,
    symbol: string
};
