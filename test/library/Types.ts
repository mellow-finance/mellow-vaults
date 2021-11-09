import { BytesLike } from "@ethersproject/bytes";
import { Contract } from "@ethersproject/contracts";
import { BigNumberish } from "@ethersproject/bignumber";
import { Address } from "hardhat-deploy/dist/types";

export type IERC20 = Address;
export type IUniV3 = Address;
export type IVaultFactory = Address;
export type IVaultGovernance = Address;
export type ILpIssuerGovernance = Address;
export type IVaultRegistry = Address;
export type IProtocolGovernance = Address;
export type IVault = Address;
export type IGatewayVault = Address;

export type ERC20 = Contract;
export type UniV3 = Contract;
export type ERC20Vault = Contract;
export type ProtocolGovernance = Contract;
export type VaultGovernance = Contract;
export type LpIssuerGovernance = Contract;
export type GatewayVault = Contract;
export type TestVaultGovernance = Contract;

export type VaultFactory = Contract;
export type Vault = Contract;

export type VaultRegistry = Contract;
export type AaveVaultGovernance = Contract;
export type ERC20VaultGovernance = Contract;
export type UniV3VaultGovernance = Contract;
export type GatewayVaultGovernance = Contract;

export type ProtocolGovernance_Params = {
    permissionless: boolean;
    maxTokensPerVault: BigNumberish;
    governanceDelay: BigNumberish;
    strategyPerformanceFee: BigNumberish;
    protocolPerformanceFee: BigNumberish;
    protocolExitFee: BigNumberish;
    protocolTreasury: Address;
};
export type ProtocolGovernance_constructorArgs = {
    admin: Address;
};

export type LpIssuerGovernance_constructorArgs = {
    registry: IVaultRegistry;
    protocolGovernance: IProtocolGovernance;
    factory: IVaultFactory;
};

/**
 * @dev creates IVault
 */
export type VaultFactory_deployVault = {
    vaultGovernance: IVaultGovernance;
    options: BytesLike;
};
export type ERC20VaultFactory_deployVault = VaultFactory_deployVault;
export type AaveVaultFactory_deployVault = VaultFactory_deployVault;
export type UniV3VaultFactory_deployVault = VaultFactory_deployVault;
export type GatewayVaultFactory_deployVault = VaultFactory_deployVault;
export type ERC20Vault_constructorArgs = {
    vaultGovernance_: IVaultGovernance;
    vaultTokens_: ERC20[];
};
export type AaveVault_constructorArgs = {
    vaultGovernance_: IVaultGovernance;
    vaultTokens_: ERC20[];
};
export type UniV3Vault_constructorArgs = {
    vaultGovernance_: IVaultGovernance;
    vaultTokens_: ERC20[];
    fee: BigNumberish;
};
export type GatewayVault_constructorArgs = {
    vaultGovernance_: IVaultGovernance;
    vaultTokens_: ERC20[];
    vaults_: IVault[];
};

/**
 * @dev IVaultGovernance
 */
export type VaultGovernance_InternalParams = {
    protocolGovernance: IProtocolGovernance;
    registry: IVaultRegistry;
};
export type VaultGovernance_constructorArgs = {
    params: VaultGovernance_InternalParams;
};
export type VaultGovernance_deployVault = {
    vaultTokens: Address[];
    options: BytesLike;
    owner: Address;
};

/**
 * @dev IVaultRegistry
 */
export type VaultRegistry_VaultKind = {
    vaultGovernance: IVaultGovernance;
    vaultFactory: IVaultFactory;
};
export type VaultRegistry_consturctorArgs = {
    name: string;
    symbol: string;
    permissionless_: boolean;
    protocolGovernance_: IProtocolGovernance;
};
export type VaultRegistry_registerVault = {
    vaultKind: BigNumberish;
    options: BytesLike;
};
export type VaultRegistry_registerVaultKind = {
    vaultKind: VaultRegistry_VaultKind;
};

export type ERC20Test_constructorArgs = {
    name: string;
    symbol: string;
};

export type VaultType = "ERC20" | "Aave" | "UniV3" | "Gateway";
export type SubVaultType = "ERC20" | "Aave" | "UniV3";
