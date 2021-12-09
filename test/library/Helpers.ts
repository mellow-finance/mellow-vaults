import { Contract, Signer, ContractFactory } from "ethers";
import { network, ethers, getNamedAccounts } from "hardhat";
import { BigNumber, BigNumberish } from "@ethersproject/bignumber";
import { filter, fromPairs, keys, KeyValuePair, map, pipe } from "ramda";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { randomBytes } from "crypto";
import { ProtocolGovernance, ERC20 } from "./Types";
import { Address } from "hardhat-deploy/dist/types";
import {
    ERC20Test_constructorArgs,
    Vault,
    VaultFactory,
    VaultGovernance,
    VaultRegistry,
} from "./Types";

export const randomAddress = () => {
    const id = randomBytes(32).toString("hex");
    const privateKey = "0x" + id;
    const wallet = new ethers.Wallet(privateKey);
    return wallet.address;
};

export const toObject = (obj: any) =>
    pipe(
        keys,
        filter((x: string) => isNaN(parseInt(x))),
        map((x) => [x, obj[x]] as KeyValuePair<string, any>),
        fromPairs
    )(obj);

export const sleepTo = async (timestamp: BigNumberish) => {
    await network.provider.send("evm_setNextBlockTimestamp", [
        BigNumber.from(timestamp).toNumber(),
    ]);
    await network.provider.send("evm_mine");
};

export const sleep = async (seconds: BigNumberish) => {
    await network.provider.send("evm_increaseTime", [
        BigNumber.from(seconds).toNumber(),
    ]);
    await network.provider.send("evm_mine");
};

export const now = () => {
    return Math.ceil(new Date().getTime() / 1000);
};

export const sortContractsByAddresses = (contracts: Contract[]) => {
    return contracts.sort((a, b) => {
        return compareAddresses(a.address, b.address);
    });
};

export const sortAddresses = (addresses: string[]) => {
    return addresses.sort((a, b) => {
        return compareAddresses(a, b);
    });
};

export const compareAddresses = (a: string, b: string) => {
    return parseInt(
        (BigNumber.from(a).toBigInt() - BigNumber.from(b).toBigInt()).toString()
    );
};

export const encodeToBytes = (
    types: string[],
    objectToEncode: readonly any[]
) => {
    let toBytes = new ethers.utils.AbiCoder();
    return toBytes.encode(types, objectToEncode);
};

export const decodeFromBytes = (types: string[], bytesToDecode: string) => {
    let fromBytes = new ethers.utils.AbiCoder();
    return fromBytes.decode(types, bytesToDecode);
};

export const addSigner = async (
    address: string
): Promise<SignerWithAddress> => {
    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [address],
    });
    await network.provider.send("hardhat_setBalance", [
        address,
        "0x1000000000000000000",
    ]);
    return await ethers.getSigner(address);
};

export const removeSigner = async (address: string) => {
    await network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [address],
    });
};

export const setTokenWhitelist = async (
    protocolGovernance: ProtocolGovernance,
    tokens: ERC20[],
    admin: SignerWithAddress | Signer
) => {
    let allowedAddresses = new Array<Address>(tokens.length);
    for (var i = 0; i < tokens.length; ++i) {
        allowedAddresses[i] = tokens[i].address;
    }
    await protocolGovernance
        .connect(admin)
        .setPendingTokenWhitelistAdd(allowedAddresses);
    await sleep(Number(await protocolGovernance.governanceDelay()));
    await protocolGovernance.connect(admin).commitTokenWhitelistAdd();
};

export async function depositW9(
    receiver: string,
    amount: BigNumberish
): Promise<void> {
    const { weth } = await getNamedAccounts();
    const w9 = await ethers.getContractAt("WERC20Test", weth);
    const sender = randomAddress();
    await withSigner(sender, async (signer) => {
        await w9.connect(signer).deposit({ value: amount });
        await w9.connect(signer).transfer(receiver, amount);
    });
}

export async function depositWBTC(
    receiver: string,
    amount: BigNumberish
): Promise<void> {
    const { wbtcRichGuy, wbtc } = await getNamedAccounts();
    const wbtcContract = await ethers.getContractAt("WERC20Test", wbtc);
    await withSigner(wbtcRichGuy, async (signer) => {
        await wbtcContract.connect(signer).transfer(receiver, amount);
    });
}

export const withSigner = async (
    address: string,
    f: (signer: SignerWithAddress) => Promise<void>
) => {
    const signer = await addSigner(address);
    await f(signer);
    await removeSigner(address);
};

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

export async function deploySubVaultSystem(options: {
    tokensCount: number;
    adminSigner: Signer;
    treasury: Address;
    vaultOwner: Address;
    dontUseTestSetup?: boolean;
}): Promise<{
    ERC20VaultFactory: VaultFactory;
    AaveVaultFactory: VaultFactory;
    UniV3VaultFactory: VaultFactory;
    LpIssuerFactory: VaultFactory;
    vaultRegistry: VaultRegistry;
    protocolGovernance: ProtocolGovernance;
    ERC20VaultGovernance: VaultGovernance;
    AaveVaultGovernance: VaultGovernance;
    UniV3VaultGovernance: VaultGovernance;
    LpIssuerGovernance: VaultGovernance;
    tokens: ERC20[];
    ERC20Vault: Vault;
    nftERC20: number;
    AnotherERC20Vault: Vault;
    anotherNftERC20: number;
    AaveVault: Vault;
    nftAave: number;
    UniV3Vault: Vault;
    nftUniV3: number;
    aTokens: ERC20[];
    chiefTrader: Contract;
    uniV3Trader: Contract;
}> {
    let vaultRegistry = await ethers.getContract("VaultRegistry");
    let protocolGovernance = await ethers.getContract("ProtocolGovernance");
    let ERC20VaultFactory = await ethers.getContract("ERC20VaultFactory");
    let AaveVaultFactory = await ethers.getContract("AaveVaultFactory");
    let UniV3VaultFactory = await ethers.getContract("UniV3VaultFactory");
    let LpIssuerFactory = await ethers.getContract("LpIssuerFactory");
    let ERC20VaultGovernance = await ethers.getContract("ERC20VaultGovernance");
    let AaveVaultGovernance = await ethers.getContract("AaveVaultGovernance");
    let UniV3VaultGovernance = await ethers.getContract("UniV3VaultGovernance");
    let LpIssuerGovernance = await ethers.getContract("LpIssuerGovernance");
    let chiefTrader = await ethers.getContract("ChiefTrader");
    let uniV3Trader = await ethers.getContract("UniV3Trader");

    const { wbtc, usdc, weth, test, deployer } = await getNamedAccounts();
    const contracts = [];
    for (const token of [wbtc, usdc, weth]) {
        const contract = await ethers.getContractAt("LpIssuer", token);
        contracts.push(contract);
        const balance = await contract.balanceOf(test);
        await withSigner(test, async (s) => {
            await contract.connect(s).transfer(deployer, balance.div(10));
        });
    }

    const vaultTokens: ERC20[] = sortContractsByAddresses(contracts).slice(
        0,
        options.tokensCount
    );
    let allowedTokens: Address[] = new Array<Address>(options.tokensCount);
    for (var i = 0; i < options.tokensCount; ++i) {
        allowedTokens[i] = vaultTokens[i].address;
    }
    await protocolGovernance
        .connect(options.adminSigner)
        .setPendingTokenWhitelistAdd(allowedTokens);
    await sleep(Number(await protocolGovernance.governanceDelay()));
    await protocolGovernance
        .connect(options.adminSigner)
        .commitTokenWhitelistAdd();
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
    optionsBytes = encodeToBytes(["uint24"], [3000]);
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

    const AnotherERC20VaultResult =
        await ERC20VaultGovernance.callStatic.deployVault(
            ...vaultDeployArgsERC20
        );
    const AnotherERC20VaultInstance = AnotherERC20VaultResult.vault;
    const anotherNftERC20 = AnotherERC20VaultResult.nft;
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
        `ERC20Vault${options?.dontUseTestSetup ? "" : "Test"}`,
        ERC20VaultInstance
    );
    const AnotherERC20VaultContract: Vault = await ethers.getContractAt(
        `ERC20Vault${options?.dontUseTestSetup ? "" : "Test"}`,
        AnotherERC20VaultInstance
    );
    const AaveVaultContract: Vault = await ethers.getContractAt(
        `AaveVault${options?.dontUseTestSetup ? "" : "Test"}`,
        AaveVaultInstance
    );
    const UniV3VaultContract: Vault = await ethers.getContractAt(
        `UniV3Vault${options?.dontUseTestSetup ? "" : "Test"}`,
        UniV3VaultInstance
    );

    let aTokens: ERC20[] = [];

    await sleep(Number(await protocolGovernance.governanceDelay()));
    // FIXME: remove this hack <
    await withSigner(ERC20VaultGovernance.address, async (signer) => {
        const [deployer] = await ethers.getSigners();
        await vaultRegistry
            .connect(signer)
            .registerVault(options.vaultOwner, options.vaultOwner);
    });
    // />
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
        AnotherERC20Vault: AnotherERC20VaultContract,
        AaveVault: AaveVaultContract,
        UniV3Vault: UniV3VaultContract,
        nftERC20: nftERC20,
        nftAave: nftAave,
        nftUniV3: nftUniV3,
        anotherNftERC20: anotherNftERC20,
        aTokens: aTokens,
        LpIssuerFactory: LpIssuerFactory,
        LpIssuerGovernance: LpIssuerGovernance,
        chiefTrader: chiefTrader,
        uniV3Trader: uniV3Trader,
    };
}
