import { 
    deployments,
    ethers
} from "hardhat";
import { 
    Signer, 
    Contract, 
    ContractFactory 
} from "ethers";
import { HardhatRuntimeEnvironment } from "hardhat/types";

// todo: move types to Types.ts
export type Address = string;
export type IERC20 = Address;
export type IVaultManager = Address;
export type IVaultFactory = Address;
export type IVaultGovernance = Address;
export type IVaultGovernanceFactory = Address;
export type IProtocolGovernance = Address;

export type ERC20 = Contract;
export type ERC20Vault = Contract;
export type ERC20VaultManager = Contract;
export type ERC20VaultFactory = Contract;
export type ProtocolGovernance = Contract;
export type VaultManagerGovernance = Contract;
export type VaultGovernanceFactory = Contract;
export type VaultGovernance = Contract;

export type TxParams = {
    from: Signer,
} | undefined;

export type ProtocolGovernance_constructor = {
    admin: Address
};

export type VaultGovernanceFactory_constructor = {
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
    options?: number[]
};
export type ERC20Vault_constructor = ERC20VaultFactory_deployVault;

export type ERC20VaultManager_constructor = {
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
    options?: number[]
};

export type VaultManagerGovernance_constructor = {
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
export type VaultGovernance_constructor = VaultGovernanceFactory_deployVaultGovernance;

export type ERC20Test_constructor = {
    name: string,
    symbol: string
};

export const deployERC20Tokens = deployments.createFixture(async (
    ctx: HardhatRuntimeEnvironment,
    options?: {
        txParams: TxParams,
        constructor: ERC20Test_constructor[],
    }
) => {
    await ctx.deployments.fixture();
    // defaults<
    let constructor: ERC20Test_constructor[] = options?.constructor ?? [];
    if (constructor.length == 0) {
        constructor = [{
            name: "Test Token",
            symbol: "TEST"
        }];
    }
    // />
    let tokens: Contract[] = [];
    for (let i: number = 0; i < constructor.length; ++i) {
        const Contract = await ethers.getContractFactory("ERC20Test");
        const contract: Contract = await Contract.deploy(
            constructor[i].name, 
            constructor[i].symbol
        );
        await contract.deployed();
        tokens.push(contract);
    }
    return tokens;
});

export const deployProtocolGovernance = deployments.createFixture(async (
    ctx: HardhatRuntimeEnvironment,
    options?: {
        txParams: TxParams,
        constructor: ProtocolGovernance_constructor
    }
) => {
    await ctx.deployments.fixture();
    // defaults<
    const constructor: ProtocolGovernance_constructor = options?.constructor ?? {
        admin: ethers.constants.AddressZero
    };
    // />
    const Contract = await ethers.getContractFactory("ProtocolGovernance");
    const contract = await Contract.deploy(
        constructor.admin
    );
    await contract.deployed();
    return contract;
});

export const deployVaultGovernanceFactory = deployments.createFixture(async (
    ctx: HardhatRuntimeEnvironment,
    _?: {
        txParams: TxParams,
        constructor: undefined
    }
) => {
    await ctx.deployments.fixture();

    const Contract = await ethers.getContractFactory("VaultGovernanceFactory");
    const contract = await Contract.deploy();
    await contract.deployed();
    return contract;
});

export const deployVaultManagerGovernance = deployments.createFixture(async (
    ctx: HardhatRuntimeEnvironment,
    options?: {
        txParams: TxParams,
        constructor: VaultManagerGovernance_constructor
    }
) => {
    await ctx.deployments.fixture();
    // defaults<
    const constructor: VaultManagerGovernance_constructor = options?.constructor ?? {
        permissionless: false,
        protocolGovernance: ethers.constants.AddressZero,
        factory: ethers.constants.AddressZero,
        governanceFactory: ethers.constants.AddressZero
    };
    // />
    const Contract = await ethers.getContractFactory("VaultManagerGovernance");
    const contract = await Contract.deploy(
        constructor.permissionless,
        constructor.protocolGovernance,
        constructor.factory,
        constructor.governanceFactory
    );
    await contract.deployed();
    return contract;
});

export const deployERC20VaultManager = deployments.createFixture(async (
    ctx: HardhatRuntimeEnvironment,
    options?: {
        txParams: TxParams,
        constructor: ERC20VaultManager_constructor
    }
) => {
    await ctx.deployments.fixture();
    // defaults<
    const constructor: ERC20VaultManager_constructor = options?.constructor ?? {
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
        constructor.name,
        constructor.symbol,
        constructor.factory,
        constructor.governanceFactory,
        constructor.permissionless,
        constructor.governance
    );
    await contract.deployed();
    return contract;
});

export const deployERC20VaultFactory = deployments.createFixture(async (
    ctx: HardhatRuntimeEnvironment,
    _?: {
        txParams: TxParams,
        constructor: undefined
    }
) => {
    await ctx.deployments.fixture();

    const Contract = await ethers.getContractFactory("ERC20VaultFactory");
    const contract = await Contract.deploy();
    await contract.deployed();
    return contract;
});

export const deployVaultGovernance = deployments.createFixture(async (
    ctx: HardhatRuntimeEnvironment,
    options?: {
        txParams: TxParams,
        constructor?: VaultGovernance_constructor,
        factory?: Contract,
    }
) => {
    await ctx.deployments.fixture();
    // defaults<
    const constructor: VaultGovernance_constructor = options?.constructor ?? {
        tokens: [],
        manager: ethers.constants.AddressZero,
        treasury: ethers.constants.AddressZero,
        admin: ethers.constants.AddressZero
    };
    // />
    let contract: Contract;
    if (options?.factory) {
        const factory: Contract = options.factory;
        contract = await factory.deployVaultGovernance(constructor);
        await contract.deployed();
    } else {
        const Contract = await ethers.getContractFactory("VaultGovernance");
        contract = await Contract.deploy(
            constructor.tokens,
            constructor.manager,
            constructor.treasury,
            constructor.admin
        );
        await contract.deployed();
    }
    return contract;
});


export const deployERC20Vault = deployments.createFixture(async (
    ctx: HardhatRuntimeEnvironment,
    options?: {
        txParams: TxParams,
        constructor?: ERC20Vault_constructor,
        factory?: Contract,
    }
) => {
    await ctx.deployments.fixture();
    // defaults<
    const constructor: ERC20Vault_constructor = options?.constructor ?? {
        vaultGovernance: ethers.constants.AddressZero,
        options: undefined
    };
    // />
    let contract: Contract;
    if (options?.factory) {
        const factory: Contract = options.factory;
        contract = await factory.deployVault(constructor);
        await contract.deployed();
    } else {
        const Contract = await ethers.getContractFactory("ERC20Vault");
        contract = await Contract.deploy(
            constructor.vaultGovernance,
            constructor.options
        );
        await contract.deployed();
    }
    return contract;
});

export const deployERC20VaultFromVaultManager = deployments.createFixture(async (
    ctx: HardhatRuntimeEnvironment,
    options?: {
        txParams: TxParams,
        factory: ERC20VaultManager,
        constructor: ERC20VaultManager_createVault | undefined,
    }
) => {
    if (!options?.factory) {
        throw new Error("factory is required");
    }
    await ctx.deployments.fixture();
    // defaults<
    const constructor: ERC20VaultManager_createVault = options?.constructor ?? {
        tokens: [],
        strategyTreasury: ethers.constants.AddressZero,
        admin: ethers.constants.AddressZero,
        options: undefined
    };
    // />
    let erc20Vault: ERC20Vault;
    let vaultGovernance: VaultGovernance;
    let nft: number;

    let vaultGovernanceAddress: IVaultGovernance;
    let erc20VaultAddress: Address;

    const factory: ERC20VaultManager = options.factory;

    [ vaultGovernanceAddress, erc20VaultAddress, nft ] = await factory.connect(constructor.admin).createVault(
        constructor.tokens,
        constructor.strategyTreasury,
        constructor.admin,
        constructor.options ?? undefined
    );

    erc20Vault = (await ethers.getContractFactory("ERC20Vault")).attach(erc20VaultAddress);
    vaultGovernance = (await ethers.getContractFactory("VaultGovernance")).attach(vaultGovernanceAddress);
    await erc20Vault.deployed();
    await vaultGovernance.deployed();

    return {
        vaultGovernance: vaultGovernance,
        erc20Vault: erc20Vault,
        nft: nft
    };
});

export const deployCommonLibrary = deployments.createFixture(async (
    ctx: HardhatRuntimeEnvironment, 
    _?: {
        txParams: TxParams
    }
) => {
    await ctx.deployments.fixture();
    const Library: ContractFactory = await ethers.getContractFactory("Common");
    const library: Contract = await Library.deploy();
    await library.deployed();
    return library;
});

/**
 * @dev From scratch.
 */
export const deployERC20VaultUniverse = deployments.createFixture(async (
    ctx: HardhatRuntimeEnvironment,
    options?: {
        txParams: TxParams,
        protocolGovernanceAdmin: Address,
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

    await ctx.deployments.fixture();

    let token_constructors: ERC20Test_constructor[] = [];
    for (let i: number = 0; i < options!.tokensCount; ++i) {
        token_constructors.push({
            name: "Test Token",
            symbol: `TEST_${i}`
        });
    }
    const tokens: Contract[] = await deployERC20Tokens({
        txParams: undefined,
        constructor: token_constructors
    });

    const protocolGovernance: Contract = await deployProtocolGovernance({
        txParams: undefined,
        constructor: {
            admin: options!.protocolGovernanceAdmin
        }
    });

    const vaultGovernanceFactory: Contract = await deployVaultGovernanceFactory();

    const erc20VaultFactory: Contract = await deployERC20VaultFactory();

    const erc20VaultManager: Contract = await deployERC20VaultManager({
        txParams: undefined,
        constructor: {
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
        txParams: undefined,
        constructor: {
            tokens: tokens.map(t => t.address),
            strategyTreasury: options!.treasury,
            admin: options!.protocolGovernanceAdmin,
            options: []
        },
        factory: erc20VaultManager
    }));

    return {
        erc20Vault: erc20Vault,
        erc20VaultManager: erc20VaultManager,
        erc20VaultFactory: erc20VaultFactory,
        vaultGovernance: vaultGovernance,
        vaultGovernanceFactory: vaultGovernanceFactory,
        protocolGovernance: protocolGovernance,
        tokens: tokens,
        nft: nft
    };
});
