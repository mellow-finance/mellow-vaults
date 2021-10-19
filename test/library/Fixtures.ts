import { 
    deployments,
    ethers
} from "hardhat";
import {
    Contract,
    ContractFactory
} from "@ethersproject/contracts";
import { Signer } from "@ethersproject/abstract-signer";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import {
    sortContractsByAddresses, 
    sleep
} from "./Helpers";
import {
    Address,
    IVaultGovernance,

    ERC20,
    ERC20Vault,
    ERC20VaultManager,
    ERC20VaultFactory,
    ProtocolGovernance,
    VaultGovernance,
    VaultGovernanceFactory,

    ERC20Test_constructorArgs,
    ERC20Vault_constructorArgs,
    ERC20VaultManager_constructorArgs,
    ERC20VaultManager_createVault,
    ProtocolGovernance_constructorArgs,
    VaultGovernance_constructorArgs,
    VaultManagerGovernance_constructorArgs,

    ProtocolGovernance_Params,
    VaultManagerGovernance,
    IVaultFactory
} from "./Types"

export const deployERC20Tokens = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
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
});

export const deployProtocolGovernance = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
    options?: {
        constructorArgs: ProtocolGovernance_constructorArgs,
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
        admin: < Address > ethers.constants.AddressZero,
        params: < ProtocolGovernance_Params > params
    };
    // />
    const Contract = await ethers.getContractFactory("ProtocolGovernance");
    const contract = await Contract.deploy(
        constructorArgs.admin
    );
    return contract;
});

export const deployVaultGovernanceFactory = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment
) => {
    const Contract = await ethers.getContractFactory("VaultGovernanceFactory");
    const contract = await Contract.deploy();
    await contract.deployed();
    return contract;
});

export const deployVaultManagerGovernance = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
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
});

export const deployERC20VaultManager = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
    options?: {
        constructorArgs: ERC20VaultManager_constructorArgs
    }
) => {
    // defaults<
    const constructorArgs: ERC20VaultManager_constructorArgs = options?.constructorArgs ?? {
        name: "Test Token",
        symbol: "TEST",
        factory: ethers.constants.AddressZero,
        governanceFactory: ethers.constants.AddressZero,
        permissionless: false,
        governance: ethers.constants.AddressZero
    };
    // />
    const Contract = await ethers.getContractFactory("ERC20VaultManager");
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
});

export const deployERC20VaultFactory = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
    __?: {
        constructorArgs: undefined
    }
) => {
    const Contract = await ethers.getContractFactory("ERC20VaultFactory");
    const contract = await Contract.deploy();
    await contract.deployed();
    return contract;
});

export const deployVaultGovernance = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
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
});


export const deployERC20Vault = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
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
});

export const deployERC20VaultFromVaultManager = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
    options?: {
        factory: ERC20VaultManager,
        adminSigner: Signer,
        constructorArgs?: ERC20VaultManager_createVault
    }
) => {
    if (!options?.factory) {
        throw new Error("factory is required");
    }
    // defaults<
    const constructorArgs: ERC20VaultManager_createVault = options?.constructorArgs ?? {
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
});

export const deployCommonLibrary = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment
) => {
    const Library: ContractFactory = await ethers.getContractFactory("Common");
    const library: Contract = await Library.deploy();
    await library.deployed();
    return library;
});

export const deployCommonLibraryTest = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
) => {
    const CommonTest: ContractFactory = await ethers.getContractFactory("CommonTest");
    const commonTest: Contract = await CommonTest.deploy();
    await commonTest.deployed();
    return commonTest;
});

/**
 * @dev From scratch.
 */
export const deployERC20VaultSystem = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
    options?: {
        protocolGovernanceAdmin: Signer,
        treasury: Address,
        tokensCount: number,
        permissionless: boolean,
        vaultManagerName?: string,
        vaultManagerSymbol?: string,
    }
) => {
    if (options === undefined) {
        throw new Error("options are required");
    }

    let token_constructorArgs: ERC20Test_constructorArgs[] = [];
    for (let i: number = 0; i < options!.tokensCount; ++i) {
        token_constructorArgs.push({
            name: "Test Token",
            symbol: `TEST_${i}`
        });
    }
    const tokens: Contract[] = await deployERC20Tokens({
        constructorArgs: token_constructorArgs
    });
    // sort tokens by address using `sortAddresses` function
    const tokensSorted: Contract[] = sortContractsByAddresses(tokens);

    const protocolGovernance: ProtocolGovernance = await deployProtocolGovernance({
        constructorArgs: {
            admin: await options!.protocolGovernanceAdmin.getAddress(),
            params: {
                maxTokensPerVault: 10,
                governanceDelay: 1,
        
                strategyPerformanceFee: 10**9,
                protocolPerformanceFee: 10**9,
                protocolExitFee: 10**9,
                protocolTreasury: ethers.constants.AddressZero,
                gatewayVaultManager: ethers.constants.AddressZero,
            }
        },
        adminSigner: options!.protocolGovernanceAdmin
    });

    const vaultGovernanceFactory: VaultGovernanceFactory = await deployVaultGovernanceFactory();

    const erc20VaultFactory: ERC20VaultFactory = await deployERC20VaultFactory();

    const erc20VaultManager: ERC20VaultManager = await deployERC20VaultManager({
        constructorArgs: {
            name: options!.vaultManagerName ?? "ERC20VaultManager",
            symbol: options!.vaultManagerSymbol ?? "E20VM",
            factory: erc20VaultFactory.address,
            governanceFactory: vaultGovernanceFactory.address,
            permissionless: options!.permissionless,
            governance: protocolGovernance.address
        }
    });
    
    let vaultGovernance: VaultGovernance;
    let erc20Vault: ERC20Vault;
    let nft: number;

    ({ vaultGovernance, erc20Vault, nft } = await deployERC20VaultFromVaultManager({
        constructorArgs: {
            tokens: tokensSorted.map(t => t.address),
            strategyTreasury: options!.treasury,
            admin: await options!.protocolGovernanceAdmin.getAddress(),
            options: []
        },
        factory: erc20VaultManager,
        adminSigner: options!.protocolGovernanceAdmin
    }));

    return {
        erc20Vault: erc20Vault,
        erc20VaultManager: erc20VaultManager,
        erc20VaultFactory: erc20VaultFactory,
        vaultGovernance: vaultGovernance,
        vaultGovernanceFactory: vaultGovernanceFactory,
        protocolGovernance: protocolGovernance,
        tokens: tokensSorted,
        nft: nft
    };
}, "Deploy ERC20Vault system");
