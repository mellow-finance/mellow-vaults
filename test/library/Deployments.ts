import { ethers, getNamedAccounts } from "hardhat";
import { Contract, ContractFactory } from "@ethersproject/contracts";
import { Signer } from "@ethersproject/abstract-signer";

import { sleep, sortContractsByAddresses } from "./Helpers";
import {
    Address,
    IVaultGovernance,
    IVaultRegistry,
    IGatewayVault,
    ERC20,
    ERC20Vault,
    ERC20VaultFactory,
    ProtocolGovernance,
    VaultGovernance,
    LpIssuerGovernance,
    VaultRegistry,
    AaveVaultFactory,
    AaveVault,
    ERC20Vault_constructorArgs,
    ProtocolGovernance_constructorArgs,
    VaultGovernance_constructorArgs,
    LpIssuerGovernance_constructorArgs,
    ProtocolGovernance_Params,
    ERC20Test_constructorArgs,
    VaultRegistry_consturctorArgs,
} from "./Types";
import { BigNumber } from "@ethersproject/bignumber";

export async function deployERC20Tokens(length: number): Promise<ERC20[]> {
    let tokens: ERC20[] = [];
    let token_constructorArgs: ERC20Test_constructorArgs[] = [];
    const Contract: ContractFactory = await ethers.getContractFactory(
        "ERC20Test"
    );

    for (let i = 0; i < length; ++i) {
        token_constructorArgs.push({
            name: "Test Token",
            symbol: `TEST_${i}`,
        });
    }

    for (let i: number = 0; i < length; ++i) {
        const contract: ERC20 = await Contract.deploy(
            token_constructorArgs[i].name + `_${i.toString()}`,
            token_constructorArgs[i].symbol
        );
        await contract.deployed();
        tokens.push(contract);
    }
    return tokens;
}

export const deployProtocolGovernance = async (options?: {
    constructorArgs?: ProtocolGovernance_constructorArgs;
    initializerArgs?: {
        params: ProtocolGovernance_Params;
    };
    adminSigner: Signer;
}) => {
    // defaults<
    const constructorArgs: ProtocolGovernance_constructorArgs =
        options?.constructorArgs ?? {
            admin:
                (await options?.adminSigner.getAddress()) ||
                (await (await ethers.getSigners())[0].getAddress()),
        };

    // />
    const Contract = await ethers.getContractFactory("ProtocolGovernance");
    const contract = await Contract.deploy(constructorArgs.admin);

    if (options?.initializerArgs) {
        await contract
            .connect(options!.adminSigner)
            .setPendingParams(options.initializerArgs.params);
        await sleep(1);
        await contract.connect(options!.adminSigner).commitParams();
    }
    return contract;
};

export const deployERC20VaultFactory = async () => {
    const Contract = await ethers.getContractFactory("ERC20VaultFactory");
    const contract = await Contract.deploy();
    await contract.deployed();
    return contract;
};

export const deployVaultRegistryAndProtocolGovernance = async (options: {
    name: string;
    symbol: string;
    adminSigner: Signer;
    treasury: Address;
}) => {
    const protocolGovernance = await deployProtocolGovernance({
        constructorArgs: {
            admin: await options.adminSigner.getAddress(),
        },
        adminSigner: options.adminSigner,
    });
    const VaultRegistryFactory: ContractFactory =
        await ethers.getContractFactory("VaultRegistry");
    let contract: VaultRegistry = await VaultRegistryFactory.deploy(
        options.name,
        options.symbol,
        protocolGovernance.address
    );
    await contract.deployed();
    await protocolGovernance.setPendingParams({
        maxTokensPerVault: BigNumber.from(10),
        governanceDelay: BigNumber.from(1),

        strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
        protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
        protocolExitFee: BigNumber.from(10 ** 9),
        protocolTreasury: options.treasury,
        vaultRegistry: contract.address,
    });
    await sleep(1);
    return {
        vaultRegistry: contract,
        protocolGovernance: protocolGovernance,
    };
};

export const deployVaultGovernance = async (options?: {
    constructorArgs?: VaultGovernance_constructorArgs;
    adminSigner: Signer;
    treasury: Address;
}) => {
    // defaults<
    const { vaultRegistry, protocolGovernance } =
        await deployVaultRegistryAndProtocolGovernance({
            name: "VaultRegistry",
            symbol: "MVR",
            adminSigner: options!.adminSigner,
            treasury:
                options?.treasury ??
                (await (await ethers.getSigners())[0].getAddress()),
        });
    const constructorArgs: VaultGovernance_constructorArgs =
        options?.constructorArgs ?? {
            params: {
                protocolGovernance: protocolGovernance.address,
                vaultRegistry: vaultRegistry.address,
            },
        };
    // />
    let contract: Contract;
    const Contract = await ethers.getContractFactory("VaultGovernance");
    contract = await Contract.deploy(constructorArgs.params);
    await contract.deployed();
    return contract;
};

export const deployCommonLibrary = async () => {
    const Library: ContractFactory = await ethers.getContractFactory("Common");
    const library: Contract = await Library.deploy();
    await library.deployed();
    return library;
};

export const deployCommonLibraryTest = async () => {
    const CommonTest: ContractFactory = await ethers.getContractFactory(
        "CommonTest"
    );
    const commonTest: Contract = await CommonTest.deploy();
    await commonTest.deployed();
    return commonTest;
};

/**
 * @dev From scratch.
 */

export async function deployAaveVaultFactory(): Promise<AaveVaultFactory> {
    const Contract = await ethers.getContractFactory("AaveVaultFactory");
    const contract = await Contract.deploy();
    await contract.deployed();
    return contract;
}

export const deployLpIssuerGovernance = async (options: {
    constructorArgs?: LpIssuerGovernance_constructorArgs;
    adminSigner?: Signer;
}) => {
    // defaults<
    const constructorArgs: LpIssuerGovernance_constructorArgs =
        options.constructorArgs ?? {
            gatewayVault: ethers.constants.AddressZero,
            protocolGovernance: ethers.constants.AddressZero,
        };
    // />
    const Contract: ContractFactory = await ethers.getContractFactory(
        "LpIssuerGovernance"
    );

    let contract: LpIssuerGovernance = await Contract.deploy(constructorArgs);
    await contract.deployed();
    return contract;
};
