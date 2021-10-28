import { BigNumber } from "@ethersproject/bignumber";
import { BytesLike } from "@ethersproject/bytes";
import { Contract } from "@ethersproject/contracts";
import { Bytes } from "@ethersproject/bytes";

// TODO: use BigNumberish type insted of BigNumber

export type Address = string;

export type IERC20 = Address;
export type IVaultManager = Address;
export type IVaultFactory = Address;
export type IVaultGovernance = Address;
export type IVaultGovernanceOld = Address;
export type IVaultGovernanceFactory = Address;
export type IProtocolGovernance = Address;
export type IGatewayVaultManager = Address;
export type ILpIssuerGovernance = Address;
export type IVault = Address;

export type ERC20 = Contract;
export type ERC20Vault = Contract;
export type ERC20VaultFactory = Contract;
export type ProtocolGovernance = Contract;
export type VaultManager = Contract;
export type VaultManagerGovernance = Contract;
export type VaultGovernanceFactory = Contract;
export type VaultGovernance = Contract;
export type VaultGovernanceOld = Contract;
export type GatewayVaultManager = Contract;
export type LpIssuerGovernance = Contract;
export type GatewayVault = Contract;

export type AaveVaultFactory = Contract;
export type AaveVaultManager = Contract;
export type AaveVault = Contract;


export type GatewayVault_constructorArgs = {
    vaultGovernance: IVaultGovernance;
    vaults: Address[];
};

export type ProtocolGovernance_Params = {
    maxTokensPerVault: BigNumber;
    governanceDelay: BigNumber;
    strategyPerformanceFee: BigNumber;
    protocolPerformanceFee: BigNumber;
    protocolExitFee: BigNumber;
    protocolTreasury: Address;
    gatewayVaultManager: IGatewayVaultManager;
};

export type ProtocolGovernance_constructorArgs = {
    admin: Address;
};

export type LpIssuerGovernance_constructorArgs = {
  gatewayVault: IVault;
  protocolGovernance: IProtocolGovernance;
};

export type VaultGovernanceFactory_constructorArgs = {
    tokens: Address[];
    manager: IVaultManager;
    treasury: Address;
    admin: Address;
};

/**
 * @dev creates IVault
 */
export type ERC20VaultFactory_deployVault = {
    vaultGovernance: IVaultGovernance;
    options: BytesLike;
};
export type ERC20Vault_constructorArgs = ERC20VaultFactory_deployVault;

export type VaultManager_constructorArgs = {
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
export type VaultManager_createVault = {
    tokens: IERC20[],
    strategyTreasury: Address,
    admin: Address,
    options: BytesLike
};

export type VaultManagerGovernance_constructorArgs = {
  permissionless: boolean;
  protocolGovernance: IProtocolGovernance;
  factory: IVaultFactory;
  governanceFactory: IVaultGovernanceFactory;
};

/**
 * @dev creates IVaultGovernanceOld
 */
export type VaultGovernanceFactory_deployVaultGovernance = {
  tokens: Address[];
  manager: IVaultManager;
  treasury: Address;
  admin: Address;
};
export type VaultGovernance_constructorArgs =
  VaultGovernanceFactory_deployVaultGovernance;

export type ERC20Test_constructorArgs = {
  name: string;
  symbol: string;
};

export type AaveTest_constructorArgs = {
    name: string;
    symbol: string;
};

export type AaveVaultManager_constructorArgs = {
    name: string,
    symbol: string,
    factory: IVaultFactory,
    governanceFactory: IVaultGovernanceFactory,
    permissionless: boolean,
    governance: IProtocolGovernance
};

export type AaveVaultManager_createVault = {
    tokens: IERC20[],
    strategyTreasury: Address,
    admin: Address,
    options: string | Bytes
};

export type GatewayVaultManager_constructorArgs = {
    name: string;
    symbol: string;
    factory: IVaultFactory;
    governanceFactory: IVaultGovernanceFactory;
    permissionless: boolean;
    governance: IProtocolGovernance;
};
