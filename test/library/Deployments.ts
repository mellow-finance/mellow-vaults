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

export const deployVaultRegistry = async (options: {
    name: string;
    symbol: string;
    permissionless: boolean;
    protocolGovernance: ProtocolGovernance;
}) => {
    const VaultRegistryFactory: ContractFactory =
        await ethers.getContractFactory("VaultRegistry");

    let contract: VaultRegistry = await VaultRegistryFactory.deploy(
        options.name,
        options.symbol,
        options.permissionless,
        options.protocolGovernance.address
    );

    await contract.deployed();
    return contract;
};

const deployVaultRegistryAndProtocolGovernance = async (options: {
    name: string;
    symbol: string;
    permissionless: boolean;
    adminSigner: Signer;
    treasury: Address;
}) => {
    const protocolGovernance = await deployProtocolGovernance({
        adminSigner: options.adminSigner,
    });
    const VaultRegistryFactory: ContractFactory =
        await ethers.getContractFactory("VaultRegistry");
    let contract: VaultRegistry = await VaultRegistryFactory.deploy(
        options.name,
        options.symbol,
        options.permissionless,
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
    await sleep(2);

    await protocolGovernance.commitParams();
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
            name: "name",
            symbol: "sym",
            permissionless: true,
            adminSigner: options!.adminSigner,
            treasury:
                options?.treasury ??
                (await (await ethers.getSigners())[0].getAddress()),
        });
    const constructorArgs: VaultGovernance_constructorArgs =
        options?.constructorArgs ?? {
            params: {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
            },
        };
    // />
    let contract: Contract;
    const Contract = await ethers.getContractFactory("VaultGovernance");
    contract = await Contract.deploy(constructorArgs.params);
    await contract.deployed();
    return contract;
};

export const deployTestVaultGovernance = async (options?: {
    constructorArgs?: VaultGovernance_constructorArgs;
    adminSigner: Signer;
    treasury: Address;
}) => {
    // defaults<
    const { vaultRegistry, protocolGovernance } =
        await deployVaultRegistryAndProtocolGovernance({
            name: "name",
            symbol: "sym",
            permissionless: true,
            adminSigner: options!.adminSigner,
            treasury:
                options?.treasury ??
                (await (await ethers.getSigners())[0].getAddress()),
        });
    const constructorArgs: VaultGovernance_constructorArgs =
        options?.constructorArgs ?? {
            params: {
                protocolGovernance: protocolGovernance.address,
                registry: vaultRegistry.address,
            },
        };
    // />
    let contract: Contract;
    const Contract = await ethers.getContractFactory("TestVaultGovernance");
    contract = await Contract.deploy(constructorArgs.params);
    await contract.deployed();
    return contract;
};

// export const deployERC20Vault = async (options?: {
//     constructorArgs?: ERC20Vault_constructorArgs;
//     factory?: ERC20VaultFactory;
// }) => {
//     // defaults<
//     const constructorArgs: ERC20Vault_constructorArgs =
//         options?.constructorArgs ?? {
//             vaultGovernance: ethers.constants.AddressZero,
//             options: [],
//         };
//     // />
//     let contract: Contract;
//     if (options?.factory) {
//         const factory: Contract = options.factory;
//         contract = await factory.deployVault(constructorArgs);
//         await contract.deployed();
//     } else {
//         const Contract = await ethers.getContractFactory("ERC20Vault");
//         contract = await Contract.deploy(
//             constructorArgs.vaultGovernance,
//             constructorArgs.options
//         );
//         await contract.deployed();
//     }
//     return contract;
// };

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

// export async function deployAaveVaultSystem(options: {
//     protocolGovernanceAdmin: Signer;
//     treasury: Address;
//     tokensCount: number;
//     permissionless: boolean;
//     vaultManagerName: string;
//     vaultManagerSymbol: string;
// }) {
//     const tokens: ERC20[] = await deployERC20Tokens(options.tokensCount);

//     const tokensSorted: ERC20[] = sortContractsByAddresses(tokens);

//     const protocolGovernance: ProtocolGovernance =
//         await deployProtocolGovernance({
//             constructorArgs: {
//                 admin: await options!.protocolGovernanceAdmin.getAddress(),
//             },
//             initializerArgs: {
//                 params: {
//                     maxTokensPerVault: BigNumber.from(10),
//                     governanceDelay: BigNumber.from(1),

//                     strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
//                     protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
//                     protocolExitFee: BigNumber.from(10 ** 9),
//                     protocolTreasury: options.treasury,
//                     vaultRegistry: ethers.constants.AddressZero,
//                 },
//             },
//             adminSigner: options.protocolGovernanceAdmin,
//         });

//     const vaultGovernanceFactory: VaultGovernanceFactory =
//         await deployVaultGovernanceFactory();

//     const AaveVaultFactory: AaveVaultFactory = await deployAaveVaultFactory();

//     const AaveVaultManager: AaveVaultManager = await deployAaveVaultManager({
//         constructor_args: {
//             name: options!.vaultManagerName ?? "AaveVaultManager",
//             symbol: options!.vaultManagerSymbol ?? "E20VM",
//             factory: AaveVaultFactory.address,
//             governanceFactory: vaultGovernanceFactory.address,
//             permissionless: options!.permissionless,
//             governance: protocolGovernance.address,
//         },
//     });

//     let vaultGovernance: VaultGovernance;
//     let AaveVault: AaveVault;
//     let nft: number;

//     ({ vaultGovernance, AaveVault, nft } =
//         await deployAaveVaultFromVaultManager({
//             constructorArgs: {
//                 tokens: tokensSorted.map((t) => t.address),
//                 strategyTreasury: options!.treasury,
//                 admin: await options!.protocolGovernanceAdmin.getAddress(),
//                 options: [],
//             },
//             factory: AaveVaultManager,
//             adminSigner: options!.protocolGovernanceAdmin,
//         }));

//     return {
//         AaveVault: AaveVault,
//         AaveVaultManager: AaveVaultManager,
//         AaveVaultFactory: AaveVaultFactory,
//         vaultGovernance: vaultGovernance,
//         vaultGovernanceFactory: vaultGovernanceFactory,
//         protocolGovernance: protocolGovernance,
//         tokens: tokensSorted,
//         nft: nft,
//     };
// }

// export const deployERC20VaultSystem = async (options: {
//     protocolGovernanceAdmin: Signer;
//     treasury: Address;
//     tokensCount: number;
//     permissionless: boolean;
//     vaultManagerName: string;
//     vaultManagerSymbol: string;
// }) => {
//     const tokens: ERC20[] = await deployERC20Tokens(options.tokensCount);
//     // sort tokens by address using `sortAddresses` function
//     let tokensSorted: ERC20[] = sortContractsByAddresses(tokens);

//     let protocolGovernance: ProtocolGovernance = await deployProtocolGovernance(
//         {
//             constructorArgs: {
//                 admin: await options.protocolGovernanceAdmin.getAddress(),
//             },
//             initializerArgs: {
//                 params: {
//                     maxTokensPerVault: BigNumber.from(10),
//                     governanceDelay: BigNumber.from(1),

//                     strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
//                     protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
//                     protocolExitFee: BigNumber.from(10 ** 9),
//                     protocolTreasury: options.treasury,
//                     vaultRegistry: ethers.constants.AddressZero,
//                 },
//             },
//             adminSigner: options.protocolGovernanceAdmin,
//         }
//     );

//     let vaultGovernanceFactory: VaultGovernanceFactory =
//         await deployVaultGovernanceFactory();

//     let erc20VaultFactory: ERC20VaultFactory = await deployERC20VaultFactory();

//     let gatewayVaultManager: GatewayVaultManager =
//         await deployGatewayVaultManager({
//             constructorArgs: {
//                 name: "gateway vault manager",
//                 symbol: "gvm",
//                 factory: erc20VaultFactory.address,
//                 governanceFactory: vaultGovernanceFactory.address,
//                 permissionless: options.permissionless,
//                 governance: protocolGovernance.address,
//             },
//         });

//     await protocolGovernance
//         .connect(options.protocolGovernanceAdmin)
//         .setPendingParams({
//             maxTokensPerVault: 10,
//             governanceDelay: 1,

//             strategyPerformanceFee: 10 * 10 ** 9,
//             protocolPerformanceFee: 2 * 10 ** 9,
//             protocolExitFee: 10 ** 9,
//             protocolTreasury: options.treasury,
//             gatewayVaultManager: gatewayVaultManager.address,
//         });

//     let vaultGovernance: VaultGovernance = await (
//         await ethers.getContractFactory("VaultGovernanceOld")
//     ).deploy(
//         tokensSorted.map((t) => t.address),
//         options!.treasury,
//         await options.protocolGovernanceAdmin.getAddress()
//     );
//     await vaultGovernance.deployed();

//     let erc20Vault: ERC20Vault = await (
//         await ethers.getContractFactory("ERC20Vault")
//     ).deploy(vaultGovernance.address);
//     await erc20Vault.deployed();
//     let anotherERC20Vault: ERC20Vault = await (
//         await ethers.getContractFactory("ERC20Vault")
//     ).deploy(vaultGovernance.address);

//     let nft: number = await erc20VaultManager.callStatic.mintVaultNft(
//         erc20Vault.address
//     );
//     await erc20VaultManager.mintVaultNft(erc20Vault.address);

//     let anotherNft: number = await erc20VaultManager.callStatic.mintVaultNft(
//         anotherERC20Vault.address
//     );
//     await erc20VaultManager.mintVaultNft(anotherERC20Vault.address);

//     return {
//         vaultGovernance: vaultGovernance,
//         erc20Vault: erc20Vault,
//         anotherERC20Vault: anotherERC20Vault,
//         nft: nft,
//         anotherNft: anotherNft,
//         tokens: tokensSorted,
//         vaultManager: erc20VaultManager,
//         protocolGovernance: protocolGovernance,
//         erc20VaultFactory: erc20VaultFactory,
//         erc20VaultManager: erc20VaultManager,
//         vaultGovernanceFactory: vaultGovernanceFactory,
//         gatewayVaultManager: gatewayVaultManager,
//     };
// };

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
