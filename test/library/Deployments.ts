import { ethers, getNamedAccounts } from "hardhat";
import { Contract, ContractFactory } from "@ethersproject/contracts";
import { Signer } from "@ethersproject/abstract-signer";

import { sleep, sortContractsByAddresses, encodeToBytes } from "./Helpers";
import {
    ERC20,
    ERC20Vault,
    AaveVault,
    UniV3Vault,
    ProtocolGovernance,
    VaultGovernance,
    LpIssuerGovernance,
    VaultRegistry,
    ProtocolGovernance_constructorArgs,
    VaultGovernance_constructorArgs,
    LpIssuerGovernance_constructorArgs,
    ProtocolGovernance_Params,
    ERC20Test_constructorArgs,
    VaultFactory,
    VaultType,
    VaultGovernance_InternalParams,
    IVaultGovernance,
    Vault,
    IGatewayVault,
    SubVaultType,
    AaveVault_constructorArgs,
    UniV3Vault_constructorArgs,
} from "./Types";
import { BigNumber } from "@ethersproject/bignumber";
import { Address } from "hardhat-deploy/dist/types";

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

export const deployProtocolGovernance = async (options: {
    constructorArgs?: ProtocolGovernance_constructorArgs;
    initializerArgs?: {
        params: ProtocolGovernance_Params;
    };
    adminSigner: Signer;
}) => {
    // defaults<
    const constructorArgs: ProtocolGovernance_constructorArgs =
        options.constructorArgs ?? {
            admin: await options.adminSigner.getAddress(),
        };
    // />
    const contractFactory: ContractFactory = await ethers.getContractFactory(
        "ProtocolGovernance"
    );
    const contract: ProtocolGovernance = await contractFactory.deploy(
        constructorArgs.admin
    );

    if (options?.initializerArgs) {
        await contract
            .connect(options!.adminSigner)
            .setPendingParams(options.initializerArgs.params);
        await sleep(Number(options.initializerArgs.params.governanceDelay));
        await contract.connect(options!.adminSigner).commitParams();
    }
    return contract;
};

export const deployVaultRegistryAndProtocolGovernance = async (options: {
    name?: string;
    symbol?: string;
    adminSigner: Signer;
    treasury: Address;
}) => {
    const protocolGovernance = await deployProtocolGovernance({
        adminSigner: options.adminSigner,
    });
    const VaultRegistryFactory: ContractFactory =
        await ethers.getContractFactory("VaultRegistry");
    let contract: VaultRegistry = await VaultRegistryFactory.deploy(
        options.name ?? "Test Vault Registry",
        options.symbol ?? "TVR",
        protocolGovernance.address
    );
    await contract.deployed();
    await protocolGovernance.connect(options.adminSigner).setPendingParams({
        permissionless: true,
        maxTokensPerVault: BigNumber.from(10),
        governanceDelay: BigNumber.from(60 * 60 * 24), // 1 day
        strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
        protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
        protocolExitFee: BigNumber.from(10 ** 9),
        protocolTreasury: options.treasury,
        vaultRegistry: contract.address,
    });
    await sleep(Number(await protocolGovernance.governanceDelay()));
    await protocolGovernance.connect(options.adminSigner).commitParams();
    return {
        vaultRegistry: contract,
        protocolGovernance: protocolGovernance,
    };
};

export async function deployVaultFactory(options: {
    VaultGovernance: IVaultGovernance;
    vaultType: VaultType;
}): Promise<VaultFactory> {
    const Contract = await ethers.getContractFactory(
        `${options.vaultType}Factory`
    );
    const contract = await Contract.deploy(options.VaultGovernance);
    return contract;
}

export const deployVaultGovernance = async (options: {
    constructorArgs: VaultGovernance_constructorArgs;
    adminSigner: Signer;
    treasury: Address;
    vaultType: VaultType;
}) => {
    let contract: Contract;
    const Contract = await ethers.getContractFactory(
        `${options.vaultType}Governance`
    );
    contract = await Contract.deploy(options.constructorArgs.params);
    await contract.deployed();
    return contract;
};

export async function deployVaultGovernanceSystem(options: {
    adminSigner: Signer;
    treasury: Address;
}): Promise<{
    ERC20VaultFactory: VaultFactory;
    AaveVaultFactory: VaultFactory;
    UniV3VaultFactory: VaultFactory;
    vaultRegistry: VaultRegistry;
    protocolGovernance: ProtocolGovernance;
    ERC20VaultGovernance: VaultGovernance;
    AaveVaultGovernance: VaultGovernance;
    UniV3VaultGovernance: VaultGovernance;
}> {
    const { vaultRegistry, protocolGovernance } =
        await deployVaultRegistryAndProtocolGovernance({
            name: "VaultRegistry",
            symbol: "MVR",
            adminSigner: options.adminSigner,
            treasury: options.treasury,
        });

    let params: VaultGovernance_InternalParams = {
        protocolGovernance: protocolGovernance.address,
        registry: vaultRegistry.address,
    };
    const contractFactoryERC20: ContractFactory =
        await ethers.getContractFactory(`ERC20VaultGovernance`);
    const contractFactoryAave: ContractFactory =
        await ethers.getContractFactory(`AaveVaultGovernance`);
    const contractFactoryUniV3: ContractFactory =
        await ethers.getContractFactory(`UniV3VaultGovernance`);
    let ERC20VaultGovernance: VaultGovernance;
    let AaveVaultGovernance: VaultGovernance;
    let UniV3VaultGovernance: VaultGovernance;
    const { aaveLendingPool } = await getNamedAccounts();
    const additionalParamsForAave = {
        lendingPool: aaveLendingPool,
    };
    const { uniswapV3PositionManager } = await getNamedAccounts();
    const additionalParamsForUniV3 = {
        positionManager: uniswapV3PositionManager,
    };
    ERC20VaultGovernance = await contractFactoryERC20.deploy(params, []);
    AaveVaultGovernance = await contractFactoryAave.deploy(
        params,
        additionalParamsForAave
    );
    UniV3VaultGovernance = await contractFactoryUniV3.deploy(
        params,
        additionalParamsForUniV3
    );
    await ERC20VaultGovernance.deployed();
    await AaveVaultGovernance.deployed();
    await UniV3VaultGovernance.deployed();
    const ERC20VaultFactory = await deployVaultFactory({
        vaultType: "ERC20Vault",
        VaultGovernance: ERC20VaultGovernance.address,
    });
    const AaveVaultFactory = await deployVaultFactory({
        vaultType: "AaveVault",
        VaultGovernance: AaveVaultGovernance.address,
    });
    const UniV3VaultFactory = await deployVaultFactory({
        vaultType: "UniV3Vault",
        VaultGovernance: UniV3VaultGovernance.address,
    });
    await ERC20VaultGovernance.initialize(ERC20VaultFactory.address);
    await AaveVaultGovernance.initialize(AaveVaultFactory.address);
    await UniV3VaultGovernance.initialize(UniV3VaultFactory.address);
    await ERC20VaultGovernance.connect(options.adminSigner).stageInternalParams(
        params
    );
    await AaveVaultGovernance.connect(options.adminSigner).stageInternalParams(
        params
    );
    await UniV3VaultGovernance.connect(options.adminSigner).stageInternalParams(
        params
    );
    await sleep(Number(await protocolGovernance.governanceDelay()));
    await ERC20VaultGovernance.connect(
        options.adminSigner
    ).commitInternalParams();
    await AaveVaultGovernance.connect(
        options.adminSigner
    ).commitInternalParams();
    await UniV3VaultGovernance.connect(
        options.adminSigner
    ).commitInternalParams();
    return {
        ERC20VaultFactory,
        AaveVaultFactory,
        UniV3VaultFactory,
        vaultRegistry,
        protocolGovernance,
        ERC20VaultGovernance,
        AaveVaultGovernance,
        UniV3VaultGovernance,
    };
}

export async function deployTestVaultGovernanceSystem(options: {
    adminSigner: Signer;
    treasury: Address;
}): Promise<{
    vaultFactory: VaultFactory;
    vaultRegistry: VaultRegistry;
    protocolGovernance: ProtocolGovernance;
    vaultGovernance: VaultGovernance;
}> {
    const { vaultRegistry, protocolGovernance } =
        await deployVaultRegistryAndProtocolGovernance({
            name: "VaultRegistry",
            symbol: "MVR",
            adminSigner: options.adminSigner,
            treasury: options.treasury,
        });

    let params: VaultGovernance_InternalParams = {
        protocolGovernance: protocolGovernance.address,
        registry: vaultRegistry.address,
    };
    const contractFactory: ContractFactory = await ethers.getContractFactory(
        `TestVaultGovernance`
    );

    let vaultGovernance: VaultGovernance;

    vaultGovernance = await contractFactory.deploy(params, []);
    await vaultGovernance.deployed();

    const ERC20VaultFactory = await deployVaultFactory({
        vaultType: "ERC20Vault",
        VaultGovernance: vaultGovernance.address,
    });

    await vaultGovernance
        .connect(options.adminSigner)
        .stageInternalParams(params);

    await sleep(Number(await protocolGovernance.governanceDelay()));
    await vaultGovernance.connect(options.adminSigner).commitInternalParams();
    return {
        vaultFactory: ERC20VaultFactory,
        vaultRegistry,
        protocolGovernance,
        vaultGovernance,
    };
}

export async function deployVaultRegistry(options: {
    name: string;
    symbol: string;
    protocolGovernance: ProtocolGovernance;
}): Promise<Contract> {
    let Contract = await ethers.getContractFactory("VaultRegistry");
    let contract = await Contract.deploy(
        options.name,
        options.symbol,
        options.protocolGovernance.address
    );
    await contract.deployed();
    return contract;
}

export async function deployCommonLibrary(): Promise<Contract> {
    const Library: ContractFactory = await ethers.getContractFactory("Common");
    const library: Contract = await Library.deploy();
    await library.deployed();
    return library;
}

export async function deployCommonLibraryTest(): Promise<Contract> {
    const CommonTest: ContractFactory = await ethers.getContractFactory(
        "CommonTest"
    );
    const commonTest: Contract = await CommonTest.deploy();
    await commonTest.deployed();
    return commonTest;
}

export const deployLpIssuerGovernance = async (options: {
    constructorArgs?: LpIssuerGovernance_constructorArgs;
    adminSigner?: Signer;
    treasury?: Address;
}) => {
    // defaults<

    let deployer: Signer;
    let treasury: Signer;

    [deployer, treasury] = await ethers.getSigners();

    const {
        ERC20VaultFactory: ERC20VaultFactory,
        vaultRegistry: vaultRegistry,
        protocolGovernance: protocolGovernance,
        ERC20VaultGovernance: ERC20VaultGovernance,
    } = await deployVaultGovernanceSystem({
        adminSigner: deployer,
        treasury: await treasury.getAddress(),
    });

    const constructorArgs: LpIssuerGovernance_constructorArgs =
        options.constructorArgs ?? {
            registry: vaultRegistry.address,
            protocolGovernance: protocolGovernance.address,
            factory: ERC20VaultFactory.address,
        };
    // />
    const Contract: ContractFactory = await ethers.getContractFactory(
        "LpIssuerGovernance"
    );

    let contract: LpIssuerGovernance = await Contract.deploy(constructorArgs);
    await contract.deployed();
    return {
        LpIssuerGovernance: contract,
        protocolGovernance: protocolGovernance,
        vaultRegistry: vaultRegistry,
        ERC20VaultFactory: ERC20VaultFactory,
    };
};

export async function deploySubVaultSystem(options: {
    tokensCount: number;
    adminSigner: Signer;
    treasury: Address;
    vaultOwner: Address;
}): Promise<{
    ERC20VaultFactory: VaultFactory;
    AaveVaultFactory: VaultFactory;
    UniV3VaultFactory: VaultFactory;
    vaultRegistry: VaultRegistry;
    protocolGovernance: ProtocolGovernance;
    ERC20VaultGovernance: VaultGovernance;
    AaveVaultGovernance: VaultGovernance;
    UniV3VaultGovernance: VaultGovernance;
    tokens: ERC20[];
    ERC20Vault: Vault;
    nftERC20: number;
    AaveVault: Vault;
    nftAave: number;
    UniV3Vault: Vault;
    nftUniV3: number;
}> {
    const {
        vaultRegistry,
        protocolGovernance,
        ERC20VaultFactory,
        AaveVaultFactory,
        UniV3VaultFactory,
        ERC20VaultGovernance,
        AaveVaultGovernance,
        UniV3VaultGovernance,
    } = await deployVaultGovernanceSystem({
        adminSigner: options.adminSigner,
        treasury: options.treasury,
    });
    const vaultTokens: ERC20[] = sortContractsByAddresses(
        await deployERC20Tokens(options.tokensCount)
    );
    await protocolGovernance
        .connect(options.adminSigner)
        .setPendingVaultGovernancesAdd([
            ERC20VaultGovernance.address,
            AaveVaultGovernance.address,
            UniV3VaultGovernance.address,
        ]);
    await sleep(Number(await protocolGovernance.governanceDelay()));
    await protocolGovernance
        .connect(options.adminSigner)
        .commitVaultGovernancesAdd();
    let optionsBytes: any = [];
    const vaultDeployArgsERC20 = [
        vaultTokens.map((token) => token.address),
        [],
        options.vaultOwner,
    ];
    const vaultDeployArgsAave = [
        vaultTokens.map((token) => token.address),
        optionsBytes,
        options.vaultOwner,
    ];
    optionsBytes = encodeToBytes(["uint"], [1]);
    const vaultDeployArgsUniV3 = [
        vaultTokens.map((token) => token.address),
        optionsBytes,
        options.vaultOwner,
    ];
    const ERC20VaultResult = await ERC20VaultGovernance.callStatic.deployVault(
        ...vaultDeployArgsERC20
    );
    const ERC20VaultInstance = ERC20VaultResult.vault;
    const nftERC20 = ERC20VaultResult.nft;
    await ERC20VaultGovernance.deployVault(...vaultDeployArgsERC20);

    const AaveVaultResult = await AaveVaultGovernance.callStatic.deployVault(
        ...vaultDeployArgsAave
    );
    const AaveVaultInstance = AaveVaultResult.vault;
    const nftAave = AaveVaultResult.nft;
    await AaveVaultGovernance.deployVault(...vaultDeployArgsAave);

    const UniV3VaultResult = await UniV3VaultGovernance.callStatic.deployVault(
        ...vaultDeployArgsUniV3
    );
    const UniV3VaultInstance = UniV3VaultResult.vault;
    const nftUniV3 = UniV3VaultResult.nft;
    await UniV3VaultGovernance.deployVault(...vaultDeployArgsUniV3);

    const ERC20VaultContract: Vault = await ethers.getContractAt(
        "ERC20Vault" as SubVaultType,
        ERC20VaultInstance
    );
    const AaveVaultContract: Vault = await ethers.getContractAt(
        "AaveVault" as SubVaultType,
        AaveVaultInstance
    );
    const UniV3VaultContract: Vault = await ethers.getContractAt(
        "UniV3Vault" as SubVaultType,
        UniV3VaultInstance
    );

    await ERC20VaultGovernance.connect(
        options.adminSigner
    ).stageDelayedStrategyParams(nftERC20, [options.treasury]);
    await AaveVaultGovernance.connect(
        options.adminSigner
    ).stageDelayedStrategyParams(nftAave, [options.treasury]);
    await UniV3VaultGovernance.connect(
        options.adminSigner
    ).stageDelayedStrategyParams(nftUniV3, [options.treasury]);
    await sleep(Number(await protocolGovernance.governanceDelay()));
    await ERC20VaultGovernance.connect(
        options.adminSigner
    ).commitDelayedStrategyParams(BigNumber.from(nftERC20));
    await AaveVaultGovernance.connect(
        options.adminSigner
    ).commitDelayedStrategyParams(BigNumber.from(nftAave));
    await UniV3VaultGovernance.connect(
        options.adminSigner
    ).commitDelayedStrategyParams(BigNumber.from(nftUniV3));
    return {
        ERC20VaultFactory: ERC20VaultFactory,
        AaveVaultFactory: AaveVaultFactory,
        UniV3VaultFactory: UniV3VaultFactory,
        vaultRegistry: vaultRegistry,
        protocolGovernance: protocolGovernance,
        ERC20VaultGovernance: ERC20VaultGovernance,
        AaveVaultGovernance: AaveVaultGovernance,
        UniV3VaultGovernance: UniV3VaultGovernance,
        tokens: vaultTokens,
        ERC20Vault: ERC20VaultContract,
        AaveVault: AaveVaultContract,
        UniV3Vault: UniV3VaultContract,
        nftERC20: nftERC20,
        nftAave: nftAave,
        nftUniV3: nftUniV3,
    };
}

export async function deploySubVaultsXGatewayVaultSystem(options: {
    adminSigner: Signer;
    vaultOwnerSigner: Signer;
    treasury: Address;
    strategy: Address;
}): Promise<{
    ERC20VaultFactory: VaultFactory;
    AaveVaultFactory: VaultFactory;
    UniV3VaultFactory: VaultFactory;
    vaultRegistry: VaultRegistry;
    protocolGovernance: ProtocolGovernance;
    ERC20VaultGovernance: VaultGovernance;
    AaveVaultGovernance: VaultGovernance;
    UniV3VaultGovernance: VaultGovernance;
    tokens: ERC20[];
    ERC20Vault: ERC20Vault;
    nftERC20: number;
    AaveVault: AaveVault;
    nftAave: number;
    UniV3Vault: UniV3Vault;
    nftUniV3: number;
    gatewayVaultGovernance: VaultGovernance;
    gatewayVaultFactory: VaultFactory;
    gatewayVault: Vault;
    gatewayNft: number;
}> {
    const {
        ERC20VaultFactory,
        AaveVaultFactory,
        UniV3VaultFactory,
        vaultRegistry,
        protocolGovernance,
        ERC20VaultGovernance,
        AaveVaultGovernance,
        UniV3VaultGovernance,
        tokens,
        ERC20Vault,
        AaveVault,
        UniV3Vault,
        nftERC20,
        nftAave,
        nftUniV3,
    } = await deploySubVaultSystem({
        tokensCount: 2,
        adminSigner: options.adminSigner,
        treasury: options.treasury,
        vaultOwner: await options.vaultOwnerSigner.getAddress(),
    });
    let args: VaultGovernance_constructorArgs = {
        params: {
            protocolGovernance: protocolGovernance.address,
            registry: vaultRegistry.address,
        },
    };
    const gatewayVaultGovernance = await deployVaultGovernance({
        constructorArgs: args,
        adminSigner: options.adminSigner,
        treasury: options.treasury,
        vaultType: "GatewayVault" as VaultType,
    });
    await protocolGovernance
        .connect(options.adminSigner)
        .setPendingVaultGovernancesAdd([gatewayVaultGovernance.address]);
    await sleep(Number(await protocolGovernance.governanceDelay()));
    await protocolGovernance
        .connect(options.adminSigner)
        .commitVaultGovernancesAdd();
    const gatewayVaultFactory = await deployVaultFactory({
        VaultGovernance: gatewayVaultGovernance.address,
        vaultType: "GatewayVault",
    });
    await gatewayVaultGovernance
        .connect(options.adminSigner)
        .stageInternalParams(args.params);
    await sleep(Number(await protocolGovernance.governanceDelay()));
    await gatewayVaultGovernance
        .connect(options.adminSigner)
        .commitInternalParams();
    await gatewayVaultGovernance.initialize(gatewayVaultFactory.address);
    await vaultRegistry.approve(
        gatewayVaultGovernance.address,
        BigNumber.from(nftERC20)
    );
    await vaultRegistry.approve(
        gatewayVaultGovernance.address,
        BigNumber.from(nftAave)
    );
    await vaultRegistry.approve(
        gatewayVaultGovernance.address,
        BigNumber.from(nftUniV3)
    );
    let gatewayVaultAddress: IGatewayVault;
    let gatewayNft: number = 0;
    const deployArgs = [
        tokens.map((token) => token.address),
        encodeToBytes(["uint256[]"], [[nftERC20, nftAave, nftUniV3]]),
        options.strategy,
    ];
    let response = await gatewayVaultGovernance.callStatic.deployVault(
        ...deployArgs
    );
    gatewayVaultAddress = response.vault;
    gatewayNft = response.nft;
    await gatewayVaultGovernance.deployVault(...deployArgs);
    const gatewayVault: Vault = await ethers.getContractAt(
        "GatewayVault",
        gatewayVaultAddress
    );
    await gatewayVaultGovernance
        .connect(options.adminSigner)
        .stageDelayedStrategyParams(gatewayNft, [
            options.treasury,
            [nftERC20, nftAave, nftUniV3],
        ]);
    await sleep(Number(await protocolGovernance.governanceDelay()));
    await gatewayVaultGovernance
        .connect(options.adminSigner)
        .commitDelayedStrategyParams(gatewayNft);
    await gatewayVaultGovernance
        .connect(options.adminSigner)
        .setStrategyParams(gatewayNft, [
            [
                BigNumber.from(10 ** 9).mul(BigNumber.from(10 ** 9)),
                BigNumber.from(10 ** 9).mul(BigNumber.from(10 ** 9)),
            ],
        ]);
    console.log(
        "StrategyParams",
        (await gatewayVaultGovernance.strategyParams(gatewayNft)).toString()
    );
    return {
        ERC20VaultFactory,
        AaveVaultFactory,
        UniV3VaultFactory,
        vaultRegistry,
        protocolGovernance,
        ERC20VaultGovernance,
        AaveVaultGovernance,
        UniV3VaultGovernance,
        tokens,
        ERC20Vault,
        AaveVault,
        UniV3Vault,
        nftERC20,
        nftAave,
        nftUniV3,
        gatewayVaultGovernance,
        gatewayVaultFactory,
        gatewayVault,
        gatewayNft,
    };
}
