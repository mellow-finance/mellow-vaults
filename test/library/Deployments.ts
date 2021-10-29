import { deployments, ethers, getNamedAccounts } from "hardhat";
import { Contract, ContractFactory } from "@ethersproject/contracts";
import { Signer } from "@ethersproject/abstract-signer";

import { sleep, sortContractsByAddresses } from "./Helpers";
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
    LpIssuerGovernance,
    GatewayVaultManager,
    ERC20Test_constructorArgs,
    ERC20Vault_constructorArgs,
    VaultManager_constructorArgs,
    VaultManager_createVault,
    ProtocolGovernance_constructorArgs,
    VaultGovernance_constructorArgs,
    VaultManagerGovernance_constructorArgs,
    LpIssuerGovernance_constructorArgs,
    GatewayVaultManager_constructorArgs,
    GatewayVault_constructorArgs,
    ProtocolGovernance_Params,
    VaultManagerGovernance,
    AaveVaultFactory,
    AaveVaultManager,
    AaveVault,
    AaveTest_constructorArgs,
    AaveVaultManager_constructorArgs,
    AaveVaultManager_createVault,
} from "./Types";
import { BigNumber } from "@ethersproject/bignumber";

export async function deployERC20Tokens(length: number): Promise<ERC20[]> {
    let tokens: ERC20[] = [];
    let token_constructorArgs: AaveTest_constructorArgs[] = [];
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
            token_constructorArgs[i].name + `_{i.toString()}`,
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

export const deployVaultGovernanceFactory = async () => {
    const Contract = await ethers.getContractFactory("VaultGovernanceFactory");
    const contract = await Contract.deploy();
    await contract.deployed();
    return contract;
};

export const deployVaultManagerGovernance = async (options?: {
    constructorArgs: VaultManagerGovernance_constructorArgs;
    adminSigner?: Signer;
}) => {
    // defaults<
    const adminSigner: Signer =
        options?.adminSigner ?? (await ethers.getSigners())[0];
    const constructorArgs: VaultManagerGovernance_constructorArgs =
        options?.constructorArgs ?? {
            permissionless: false,
            protocolGovernance: (
                await deployProtocolGovernance({ adminSigner: adminSigner })
            ).address,
            factory: (await deployERC20VaultFactory()).address,
            governanceFactory: (await deployVaultGovernanceFactory()).address,
        };
    // />
    const contractFactory: ContractFactory = await ethers.getContractFactory(
        "VaultManagerGovernance"
    );
    const contract: VaultManagerGovernance = await contractFactory
        .connect(adminSigner)
        .deploy(
            constructorArgs.permissionless,
            constructorArgs.protocolGovernance,
            constructorArgs.factory,
            constructorArgs.governanceFactory
        );
    await contract.deployed();
    return contract;
};

export const deployVaultManagerTest = async (options?: {
    constructorArgs: VaultManager_constructorArgs;
}) => {
    // defaults<
    const constructorArgs: VaultManager_constructorArgs =
        options?.constructorArgs ?? {
            name: "Test Token",
            symbol: "TEST",
            factory: ethers.constants.AddressZero,
            governanceFactory: ethers.constants.AddressZero,
            permissionless: false,
            governance: ethers.constants.AddressZero,
        };
    // />
    const Contract = await ethers.getContractFactory("VaultManagerTest");
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

export const deployVaultGovernance = async (options?: {
    constructorArgs?: VaultGovernance_constructorArgs;
    factory?: Contract;
}) => {
    // defaults<
    const constructorArgs: VaultGovernance_constructorArgs =
        options?.constructorArgs ?? {
            tokens: [],
            manager: ethers.constants.AddressZero,
            treasury: ethers.constants.AddressZero,
            admin: ethers.constants.AddressZero,
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

export const deployGatewayVaultManager = async (options: {
    constructorArgs: GatewayVaultManager_constructorArgs;
}) => {
    const Contract: ContractFactory = await ethers.getContractFactory(
        "GatewayVaultManager"
    );
    const contract: GatewayVaultManager = await Contract.deploy(
        options.constructorArgs.name,
        options.constructorArgs.symbol,
        options.constructorArgs.factory,
        options.constructorArgs.governanceFactory,
        options.constructorArgs.permissionless,
        options.constructorArgs.governance
    );
    await contract.deployed();
    return contract;
};

export const deployERC20Vault = async (options?: {
    constructorArgs?: ERC20Vault_constructorArgs;
    factory?: ERC20VaultFactory;
}) => {
    // defaults<
    const constructorArgs: ERC20Vault_constructorArgs =
        options?.constructorArgs ?? {
            vaultGovernance: ethers.constants.AddressZero,
            options: [],
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

export const deployERC20VaultFromVaultManager = async (options: {
    factory: VaultManager;
    adminSigner: Signer;
    constructorArgs?: VaultManager_createVault;
}) => {
    // defaults<
    const constructorArgs: VaultManager_createVault =
        options.constructorArgs ?? {
            tokens: [],
            strategyTreasury: ethers.constants.AddressZero,
            admin: ethers.constants.AddressZero,
            options: [],
        };
    // />
    let erc20Vault: ERC20Vault;
    let vaultGovernance: VaultGovernance;
    let nft: number;

    let vaultGovernanceAddress: IVaultGovernance;
    let erc20VaultAddress: Address;

    [vaultGovernanceAddress, erc20VaultAddress, nft] = await options.factory
        .connect(options.adminSigner)
        .callStatic.createVault(
            constructorArgs.tokens,
            constructorArgs.strategyTreasury,
            constructorArgs.admin,
            constructorArgs.options
        );

    erc20Vault = await ethers.getContractAt("ERC20Vault", erc20VaultAddress);
    vaultGovernance = await ethers.getContractAt(
        "VaultGovernance",
        vaultGovernanceAddress
    );

    return {
        vaultGovernance: vaultGovernance,
        erc20Vault: erc20Vault,
        nft: nft,
    };
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

export async function deployAaveVaultManager(options?: {
    constructor_args: AaveVaultManager_constructorArgs;
}): Promise<AaveVaultManager> {
    const constructorArgs: AaveVaultManager_constructorArgs =
        options?.constructor_args ?? {
            name: "Test Token",
            symbol: "TEST",
            factory: ethers.constants.AddressZero,
            governanceFactory: ethers.constants.AddressZero,
            permissionless: false,
            governance: ethers.constants.AddressZero,
        };

    const Contract = await ethers.getContractFactory("AaveVaultManager");
    const { aaveLendingPool } = await getNamedAccounts();
    const contract = await Contract.deploy(
        constructorArgs.name,
        constructorArgs.symbol,
        constructorArgs.factory,
        constructorArgs.governanceFactory,
        constructorArgs.permissionless,
        constructorArgs.governance,
        aaveLendingPool
    );
    await contract.deployed();
    return contract;
}

export async function deployAaveVaultFromVaultManager(options?: {
    factory: AaveVaultManager;
    adminSigner: Signer;
    constructorArgs?: AaveVaultManager_createVault;
}): Promise<{
    vaultGovernance: VaultGovernance;
    AaveVault: AaveVault;
    nft: number;
}> {
    if (!options?.factory) {
        throw new Error("Factory is required");
    }

    const constructorArgs: AaveVaultManager_createVault =
        options?.constructorArgs ?? {
            tokens: [],
            strategyTreasury: ethers.constants.AddressZero,
            admin: ethers.constants.AddressZero,
            options: [],
        };

    let AaveVault: AaveVault;
    let vaultGovernance: VaultGovernance;
    let nft: number;

    let vaultGovernanceAddress: string;
    let AaveVaultAddress: Address;

    [vaultGovernanceAddress, AaveVaultAddress, nft] = await options!.factory
        .connect(options.adminSigner)
        .callStatic.createVault(
            constructorArgs.tokens,
            constructorArgs.strategyTreasury,
            constructorArgs.admin,
            constructorArgs.options
        );

    await options!.factory
        .connect(options.adminSigner)
        .createVault(
            constructorArgs.tokens,
            constructorArgs.strategyTreasury,
            constructorArgs.admin,
            constructorArgs.options
        );

    AaveVault = await ethers.getContractAt("AaveVault", AaveVaultAddress);
    vaultGovernance = await ethers.getContractAt(
        "VaultGovernance",
        vaultGovernanceAddress
    );

    return {
        vaultGovernance: vaultGovernance,
        AaveVault: AaveVault,
        nft: nft,
    };
}

export async function deployAaveVaultSystem(options: {
    protocolGovernanceAdmin: Signer;
    treasury: Address;
    tokensCount: number;
    permissionless: boolean;
    vaultManagerName: string;
    vaultManagerSymbol: string;
}) {
    const tokens: ERC20[] = await deployERC20Tokens(options.tokensCount);

    const tokensSorted: ERC20[] = sortContractsByAddresses(tokens);

    const protocolGovernance: ProtocolGovernance =
        await deployProtocolGovernance({
            constructorArgs: {
                admin: await options!.protocolGovernanceAdmin.getAddress(),
            },
            initializerArgs: {
                params: {
                    maxTokensPerVault: BigNumber.from(10),
                    governanceDelay: BigNumber.from(1),

                    strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                    protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                    protocolExitFee: BigNumber.from(10 ** 9),
                    protocolTreasury: options.treasury,
                    vaultRegistry: ethers.constants.AddressZero,
                },
            },
            adminSigner: options.protocolGovernanceAdmin,
        });

    const vaultGovernanceFactory: VaultGovernanceFactory =
        await deployVaultGovernanceFactory();

    const AaveVaultFactory: AaveVaultFactory = await deployAaveVaultFactory();

    const AaveVaultManager: AaveVaultManager = await deployAaveVaultManager({
        constructor_args: {
            name: options!.vaultManagerName ?? "AaveVaultManager",
            symbol: options!.vaultManagerSymbol ?? "E20VM",
            factory: AaveVaultFactory.address,
            governanceFactory: vaultGovernanceFactory.address,
            permissionless: options!.permissionless,
            governance: protocolGovernance.address,
        },
    });

    let vaultGovernance: VaultGovernance;
    let AaveVault: AaveVault;
    let nft: number;

    ({ vaultGovernance, AaveVault, nft } =
        await deployAaveVaultFromVaultManager({
            constructorArgs: {
                tokens: tokensSorted.map((t) => t.address),
                strategyTreasury: options!.treasury,
                admin: await options!.protocolGovernanceAdmin.getAddress(),
                options: [],
            },
            factory: AaveVaultManager,
            adminSigner: options!.protocolGovernanceAdmin,
        }));

    return {
        AaveVault: AaveVault,
        AaveVaultManager: AaveVaultManager,
        AaveVaultFactory: AaveVaultFactory,
        vaultGovernance: vaultGovernance,
        vaultGovernanceFactory: vaultGovernanceFactory,
        protocolGovernance: protocolGovernance,
        tokens: tokensSorted,
        nft: nft,
    };
}

export const deployERC20VaultSystem = async (options: {
    protocolGovernanceAdmin: Signer;
    treasury: Address;
    tokensCount: number;
    permissionless: boolean;
    vaultManagerName: string;
    vaultManagerSymbol: string;
}) => {
    const tokens: ERC20[] = await deployERC20Tokens(options.tokensCount);
    // sort tokens by address using `sortAddresses` function
    let tokensSorted: ERC20[] = sortContractsByAddresses(tokens);

    let protocolGovernance: ProtocolGovernance = await deployProtocolGovernance(
        {
            constructorArgs: {
                admin: await options.protocolGovernanceAdmin.getAddress(),
            },
            initializerArgs: {
                params: {
                    maxTokensPerVault: BigNumber.from(10),
                    governanceDelay: BigNumber.from(1),

                    strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
                    protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
                    protocolExitFee: BigNumber.from(10 ** 9),
                    protocolTreasury: options.treasury,
                    vaultRegistry: ethers.constants.AddressZero,
                },
            },
            adminSigner: options.protocolGovernanceAdmin,
        }
    );

    let vaultGovernanceFactory: VaultGovernanceFactory =
        await deployVaultGovernanceFactory();

    let erc20VaultFactory: ERC20VaultFactory = await deployERC20VaultFactory();

    let gatewayVaultManager: GatewayVaultManager =
        await deployGatewayVaultManager({
            constructorArgs: {
                name: "gateway vault manager",
                symbol: "gvm",
                factory: erc20VaultFactory.address,
                governanceFactory: vaultGovernanceFactory.address,
                permissionless: options.permissionless,
                governance: protocolGovernance.address,
            },
        });

    await protocolGovernance
        .connect(options.protocolGovernanceAdmin)
        .setPendingParams({
            maxTokensPerVault: 10,
            governanceDelay: 1,

            strategyPerformanceFee: 10 * 10 ** 9,
            protocolPerformanceFee: 2 * 10 ** 9,
            protocolExitFee: 10 ** 9,
            protocolTreasury: options.treasury,
            gatewayVaultManager: gatewayVaultManager.address,
        });

    let vaultGovernance: VaultGovernance = await (
        await ethers.getContractFactory("VaultGovernanceOld")
    ).deploy(
        tokensSorted.map((t) => t.address),
        erc20VaultManager.address,
        options!.treasury,
        await options.protocolGovernanceAdmin.getAddress()
    );
    await vaultGovernance.deployed();

    let erc20Vault: ERC20Vault = await (
        await ethers.getContractFactory("ERC20Vault")
    ).deploy(vaultGovernance.address);
    await erc20Vault.deployed();
    let anotherERC20Vault: ERC20Vault = await (
        await ethers.getContractFactory("ERC20Vault")
    ).deploy(vaultGovernance.address);

    let nft: number = await erc20VaultManager.callStatic.mintVaultNft(
        erc20Vault.address
    );
    await erc20VaultManager.mintVaultNft(erc20Vault.address);

    let anotherNft: number = await erc20VaultManager.callStatic.mintVaultNft(
        anotherERC20Vault.address
    );
    await erc20VaultManager.mintVaultNft(anotherERC20Vault.address);

    return {
        vaultGovernance: vaultGovernance,
        erc20Vault: erc20Vault,
        anotherERC20Vault: anotherERC20Vault,
        nft: nft,
        anotherNft: anotherNft,
        tokens: tokensSorted,
        vaultManager: erc20VaultManager,
        protocolGovernance: protocolGovernance,
        erc20VaultFactory: erc20VaultFactory,
        erc20VaultManager: erc20VaultManager,
        vaultGovernanceFactory: vaultGovernanceFactory,
        gatewayVaultManager: gatewayVaultManager,
    };
};

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
