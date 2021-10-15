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

type FixtureParams = {
    owner: Signer,
} | undefined;

export const setupCommonLibrary = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment, __: any
) => {
    await deployments.fixture();
    const CommonLibrary: ContractFactory = await ethers.getContractFactory("Common");
    const commonLibrary: Contract = await CommonLibrary.deploy();
    return commonLibrary;
});

export const setupERC20Token = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment, 
    options: {
        params: FixtureParams,
        id: string
    } | undefined
) => {
    await deployments.fixture();
    const owner: Signer = options?.params?.owner || (await ethers.getSigners())[0];
    const symbol: string = "TST" + (options?.id || "");
    const ERC20TestToken: ContractFactory = await ethers.getContractFactory("ERC20Test", owner);
    return await ERC20TestToken.deploy(symbol, symbol);
});

export const setupProtocolGovernance = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment, 
    options: {
        params: FixtureParams,
        admin: Signer
    } | undefined
) => {
    await deployments.fixture();
    const owner: Signer = options?.params?.owner || (await ethers.getSigners())[0];  // todo: implement ParamsBuilder or smth
    const admin: Signer = options?.admin || owner;
    const ProtocolGovernance = await ethers.getContractFactory("ProtocolGovernance", owner);
    const protocolGovernance = ProtocolGovernance.deploy(await admin.getAddress());
    return protocolGovernance;
});

export const setupERC20VaultFactory = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
    options: {
        params: FixtureParams,
    } | undefined
) => {
    await deployments.fixture();
    const owner: Signer = options?.params?.owner || (await ethers.getSigners())[0];
    const ERC20VaultFactory = await ethers.getContractFactory("ERC20VaultFactory", owner);
    return await ERC20VaultFactory.deploy();
});

export const setupVaultManager = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
    options: {
        params: FixtureParams,
        name: string, 
        symbol: string,
        permissionless: boolean,
        tokensCount: number,
        factory: Contract | undefined,
        protocolGovernance: Contract | undefined
    } | undefined
) => {
    await deployments.fixture();
    const owner: Signer = options?.params?.owner || (await ethers.getSigners())[0];
    const factory = options?.factory || await setupERC20VaultFactory({ params: options?.params });
    const protocolGovernance = options?.protocolGovernance || await setupProtocolGovernance({ 
        params: options?.params,
        admin: owner  // todo: configure admin
    });
    const VaultManager = await ethers.getContractFactory("VaultManager", owner);
    const vaultManager = VaultManager.deploy(
        options?.name, 
        options?.symbol, 
        await factory.getAddress(), 
        options?.permissionless,
        await protocolGovernance.getAddress()
    );
    return vaultManager;
});

export const setupERC20Vault = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
    options: {
        params: FixtureParams,
        treasury: Signer,
        admin: Signer,
        tokensCount: number,
        calldata: number[]
    } | undefined
) => {
    await deployments.fixture();
    const owner: Signer = options?.params?.owner || (await ethers.getSigners())[0];
    const admin: Signer = options?.admin || owner;
    const treasury: Signer = options?.treasury || owner;
    const tokenCount = options?.tokensCount || 1;
    let tokens: Contract[] = [];
    for (let i: number = 0; i < tokenCount; i++) {
        const token: Contract = await setupERC20Token({
            params: options?.params,
            id: i.toString()
        });
        tokens.push(token);
    }
    const erc20VaultFactory = await setupERC20VaultFactory({ params: options?.params });
    const erc20Vault = await erc20VaultFactory.deployVault(
        tokens,
        await treasury.getAddress(),
        await admin.getAddress(),
        options?.calldata || []
    );
    return [
        erc20Vault,
        tokens
    ];
});

export const setupVaultGovernanceFactory = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
    options: {
        params: FixtureParams,
    } | undefined
) => {

});

export const setupVaultManagerGovernance = deployments.createFixture(async (
    _: HardhatRuntimeEnvironment,
    options: {
        params: FixtureParams,
        permissionless: boolean,
        admin: Signer | undefined,
        protocolGovernance: Contract | undefined,
        factory: Contract | undefined
    } | undefined
) => {
    await deployments.fixture();
    const owner: Signer = options?.params?.owner || (await ethers.getSigners())[0];
    const admin: Signer = options?.admin || owner;
    const protocolGovernance: Contract = options?.protocolGovernance || await setupProtocolGovernance({
        params: options?.params,
        admin: admin
    });
    const factory: Contract = options?.factory || await setupERC20VaultFactory({
        params: options?.params
    });
    const VaultManagerGovernance = await ethers.getContractFactory("VaultManagerGovernance", owner);
    const vaultManagerGovernance = VaultManagerGovernance.deploy(
        options?.permissionless || true,
        protocolGovernance.address,
        factory.address
    );
    return vaultManagerGovernance;
});
