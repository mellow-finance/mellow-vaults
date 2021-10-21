import { ethers } from "hardhat";
import {
    Contract,
    ContractFactory
} from "@ethersproject/contracts";
import { Signer } from "@ethersproject/abstract-signer";

import { sortContractsByAddresses } from "./Helpers";
import {
    Address,
    IVaultGovernance,

    ERC20,
    ERC20Vault,
    ERC20VaultFactory,
    ProtocolGovernance,
    VaultManager,
    VaultGovernance,
    VaultGovernanceFactory,

    ERC20Test_constructorArgs,
    ERC20Vault_constructorArgs,
    VaultManager_constructorArgs,
    VaultManager_createVault,
    ProtocolGovernance_constructorArgs,
    VaultGovernance_constructorArgs,
    VaultManagerGovernance_constructorArgs,

    ProtocolGovernance_Params,
    VaultManagerGovernance
} from "./Types"

export const deployERC20Tokens = async (
    options?: {
        constructorArgs: ERC20Test_constructorArgs[],
    }
) => {
    // defaults<
    let constructorArgs: ERC20Test_constructorArgs[] = options?.constructorArgs ?? [];
    if (constructorArgs.length == 0) {
        constructorArgs = [{
            name: "Test Token",
            symbol: "TEST"
        }];
    }
    // />
    let tokens: ERC20[] = [];
    for (let i: number = 0; i < constructorArgs.length; ++i) {
        const Contract: ContractFactory = await ethers.getContractFactory("ERC20Test");
        const contract: ERC20 = await Contract.deploy(
            constructorArgs[i].name, 
            constructorArgs[i].symbol
        );
        await contract.deployed();
        tokens.push(contract);
    }
    return tokens;
};

export const deployProtocolGovernance = async (
    options?: {
        constructorArgs?: ProtocolGovernance_constructorArgs,
        adminSigner: Signer
    }
) => {
    // defaults<
    const params: ProtocolGovernance_Params = options?.constructorArgs?.params ?? {
        maxTokensPerVault: 10,
        governanceDelay: 1,

        strategyPerformanceFee: 10**9,
        protocolPerformanceFee: 10**9,
        protocolExitFee: 10**9,
        protocolTreasury: ethers.constants.AddressZero,
        gatewayVaultManager: ethers.constants.AddressZero,
    };
    const constructorArgs: ProtocolGovernance_constructorArgs = options?.constructorArgs ?? {
        admin: await options?.adminSigner.getAddress() || ethers.constants.AddressZero,
        params: params
    };
    // />
    const Contract = await ethers.getContractFactory("ProtocolGovernance");
    const contract = await Contract.deploy(
        constructorArgs.admin,
        constructorArgs.params
    );
    return contract;
};

export const deployVaultGovernanceFactory = async () => {
    const Contract = await ethers.getContractFactory("VaultGovernanceFactory");
    const contract = await Contract.deploy();
    await contract.deployed();
    return contract;
};

export const deployVaultManagerGovernance = async (
    options?: {
        constructorArgs: VaultManagerGovernance_constructorArgs
    }
) => {
    // defaults<
    const constructorArgs: VaultManagerGovernance_constructorArgs = options?.constructorArgs ?? {
        permissionless: false,
        protocolGovernance: ethers.constants.AddressZero,
        factory: ethers.constants.AddressZero,
        governanceFactory: ethers.constants.AddressZero,
    };
    // />
    const contractFactory: ContractFactory = await ethers.getContractFactory("VaultManagerGovernance");
    const contract: VaultManagerGovernance = await contractFactory.deploy(
        constructorArgs.permissionless,
        constructorArgs.protocolGovernance,
        constructorArgs.factory,
        constructorArgs.governanceFactory
    );
    await contract.deployed();
    return contract;
};

export const deployVaultManager = async (
    options?: {
        constructorArgs: VaultManager_constructorArgs
    }
) => {
    // defaults<
    const constructorArgs: VaultManager_constructorArgs = options?.constructorArgs ?? {
        name: "Test Token",
        symbol: "TEST",
        factory: ethers.constants.AddressZero,
        governanceFactory: ethers.constants.AddressZero,
        permissionless: false,
        governance: ethers.constants.AddressZero
    };
    // />
    const Contract = await ethers.getContractFactory("VaultManager");
    const contract = await Contract.deploy(
        constructorArgs.name,
        constructorArgs.symbol,
        constructorArgs.factory,
        constructorArgs.governanceFactory,
        constructorArgs.permissionless,
        constructorArgs.governance
    );
    await contract.deployed();
    return contract;
};

export const deployERC20VaultFactory = async () => {
    const Contract = await ethers.getContractFactory("ERC20VaultFactory");
    const contract = await Contract.deploy();
    await contract.deployed();
    return contract;
};

export const deployVaultGovernance = async (
    options?: {
        constructorArgs?: VaultGovernance_constructorArgs,
        factory?: Contract,
    }
) => {
    // defaults<
    const constructorArgs: VaultGovernance_constructorArgs = options?.constructorArgs ?? {
        tokens: [],
        manager: ethers.constants.AddressZero,
        treasury: ethers.constants.AddressZero,
        admin: ethers.constants.AddressZero
    };
    // />
    let contract: Contract;
    if (options?.factory) {
        const factory: Contract = options.factory;
        contract = await factory.deployVaultGovernance(constructorArgs);
        await contract.deployed();
    } else {
        const Contract = await ethers.getContractFactory("VaultGovernance");
        contract = await Contract.deploy(
            constructorArgs.tokens,
            constructorArgs.manager,
            constructorArgs.treasury,
            constructorArgs.admin
        );
        await contract.deployed();
    }
    return contract;
};


export const deployERC20Vault = async (
    options?: {
        constructorArgs?: ERC20Vault_constructorArgs,
        factory?: ERC20VaultFactory,
    }
) => {
    // defaults<
    const constructorArgs: ERC20Vault_constructorArgs = options?.constructorArgs ?? {
        vaultGovernance: ethers.constants.AddressZero,
        options: []
    };
    // />
    let contract: Contract;
    if (options?.factory) {
        const factory: Contract = options.factory;
        contract = await factory.deployVault(constructorArgs);
        await contract.deployed();
    } else {
        const Contract = await ethers.getContractFactory("ERC20Vault");
        contract = await Contract.deploy(
            constructorArgs.vaultGovernance,
            constructorArgs.options
        );
        await contract.deployed();
    }
    return contract;
};

export const deployERC20VaultFromVaultManager = async (
    options?: {
        factory: VaultManager,
        adminSigner: Signer,
        constructorArgs?: VaultManager_createVault
    }
) => {
    if (!options?.factory) {
        throw new Error("factory is required");
    }
    // defaults<
    const constructorArgs: VaultManager_createVault = options?.constructorArgs ?? {
        tokens: [],
        strategyTreasury: ethers.constants.AddressZero,
        admin: ethers.constants.AddressZero,
        options: []
    };
    // />
    let erc20Vault: ERC20Vault;
    let vaultGovernance: VaultGovernance;
    let nft: number;

    let vaultGovernanceAddress: IVaultGovernance;
    let erc20VaultAddress: Address;

    [
        vaultGovernanceAddress,
        erc20VaultAddress,
        nft
    ] = await options!.factory.connect(options.adminSigner).callStatic.createVault(
        constructorArgs.tokens,
        constructorArgs.strategyTreasury,
        constructorArgs.admin,
        constructorArgs.options
    );

    erc20Vault = await ethers.getContractAt("ERC20Vault", erc20VaultAddress);
    vaultGovernance = await ethers.getContractAt("VaultGovernance", vaultGovernanceAddress);

    return {
        vaultGovernance: vaultGovernance,
        erc20Vault: erc20Vault,
        nft: nft
    };
};

export const deployCommonLibrary = async () => {
    const Library: ContractFactory = await ethers.getContractFactory("Common");
    const library: Contract = await Library.deploy();
    await library.deployed();
    return library;
};

export const deployCommonLibraryTest = async () => {
    const CommonTest: ContractFactory = await ethers.getContractFactory("CommonTest");
    const commonTest: Contract = await CommonTest.deploy();
    await commonTest.deployed();
    return commonTest;
};
